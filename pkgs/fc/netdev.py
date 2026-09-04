import argparse
import contextlib
import fcntl
import json
import signal
import subprocess
import sys
from pathlib import Path

from netaddr import EUI, AddrFormatError, mac_unix_expanded

INTERFACE_RENAME_LOCKFILE = "/var/lock/interface-rename.lock"
LOCK_TIMEOUT = 60

RENAME_LIMIT = 60
INTEL_DRIVER_NAMES = ["e1000", "e1000e", "igb", "ixgbe", "i40e"]


def fatal(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


class LockTimeoutError(Exception):
    pass


@contextlib.contextmanager
def interface_renaming_lock():
    lockfile = Path(INTERFACE_RENAME_LOCKFILE)

    def alarm_handler(sig, frame):
        raise LockTimeoutError()

    print("Acquiring interface renaming lock ...")

    lockfile.touch()
    with open(lockfile, "r") as f:
        old_handler = signal.signal(signal.SIGALRM, alarm_handler)
        signal.alarm(LOCK_TIMEOUT)

        try:
            fcntl.flock(f, fcntl.LOCK_EX)
        except LockTimeoutError:
            fatal("Timed out acquiring interface renaming lock")
        except OSError as ex:
            fatal(f"Could not acquire interface renaming lock: {ex}")

        signal.alarm(0)
        signal.signal(signal.SIGALRM, old_handler)

        print("Got interface renaming lock ...")

        yield

        print("Releasing lock")
        fcntl.flock(f, fcntl.LOCK_UN)


def ip_link(args, **kwargs):
    cmd = ["ip", "link"]
    cmd.extend(args)
    if "check" not in kwargs:
        # check by default unless specified otherwise.
        kwargs["check"] = True
    return subprocess.run(cmd, **kwargs)  # noqa: PLW1510


def ip_link_show():
    data = subprocess.check_output(["ip", "-d", "-j", "link", "show"])
    return json.loads(data.decode("utf-8"))


def ethtool(args, **kwargs):
    cmd = ["ethtool"]
    cmd.extend(args)
    return subprocess.run(cmd, **kwargs)  # noqa: PLW1510


def driver_matches_intel(iface):
    data = subprocess.check_output(["ethtool", "-i", iface])
    data = data.decode("utf-8")
    for line in data.splitlines():
        if not line.startswith("driver: "):
            continue
        driver = line.removeprefix("driver: ")
        driver = driver.strip()
        return driver in INTEL_DRIVER_NAMES
    return False


def rename_to_neutral(iface, set_first_down=False):
    # rename interface from its current name to a neutral name by
    # repeated brute force
    for counter in range(RENAME_LIMIT):
        # does the interface (still) exist under its current name?
        show_proc = ip_link(
            ["show", "dev", iface], stdout=subprocess.DEVNULL, check=False
        )
        if show_proc.returncode != 0:
            # interface no longer found under current name, success!
            return

        # ensure the interface is set down on the first pass if it
        # does exist if this has not been handled by the caller.
        if not counter and set_first_down:
            print(f"'{iface}' is still being used, trying to clean up")
            ip_link(["set", iface, "down"])

        # attempt to rename the interface from its current name to the
        # next neutral name. note that an interface with the current
        # neutral name may already exist, which would cause the
        # renaming to fail, but we'll test that on the next iteration.
        target = f"eth{counter}"
        ip_link(["set", iface, "name", target], check=False)

        # the current name may be an interface altname, in which case
        # stripping the altname will also satisfy our exit
        # condition. we also don't care if this succeeds, we'll test
        # on the next iteration.
        ip_link(
            ["property", "del", "altname", iface, "dev", iface], check=False
        )

    fatal(f"Could not rename interface {iface} to neutral name!")


def start(args):
    print(f"Ensuring interface name '{args.interface}' ...")

    target_name = args.interface

    current_name = None
    current_links = ip_link_show()
    for link in current_links:
        # ignore virtual kernel network devices. virtual devices are
        # always tagged with linkinfo.
        if link.get("linkinfo", {}).get("info_kind"):
            continue

        if link.get("address") == str(args.mac_address):
            current_name = link["ifname"]
            break

    if not current_name:
        fatal(
            f"ERROR: Missing interface with MAC address '{args.mac_address}'\n"
            "Found interfaces: {}".format(
                ", ".join([x["ifname"] for x in current_links])
            )
        )

    if current_name != target_name:
        print(f"Interface is currently known as '{current_name}'")
        rename_to_neutral(target_name, set_first_down=True)

        print(f"Performing rename from '{current_name}' to '{target_name}'")
        ip_link(["set", current_name, "down"])
        ip_link(["set", current_name, "name", target_name])

    if driver_matches_intel(args.interface):
        print("Enabling adaptive interrupt moderation ...")
        ethtool(["-C", args.interface, "rx-usecs", "1"])

        print("Setting ring buffer ...")
        ethtool(["-G", args.interface, "rx", "4096", "tx", "4096"])

        print("Enabling large receive offload ...")
        ethtool(["-K", args.interface, "lro", "on"])

    if not args.flow_control:
        print("Disabling flow control")
        ethtool(
            ["-A", args.interface, "autoneg", "off", "rx", "off", "tx", "off"]
        )

    ip_link(["set", args.interface, "mtu", str(args.mtu)])

    if args.label:
        label = args.label.replace("/", "-")

        show_proc = ip_link(
            ["show", "dev", label], check=False, stdout=subprocess.DEVNULL
        )
        if show_proc.returncode == 0:
            # an interface with the given altname already exists,
            # clean it up.
            #
            # XXX: this does not cover the edge case where the desired
            # label is the primary name of another interface.
            ip_link(["property", "del", "altname", label, "dev", label])

        ip_link(["property", "add", "altname", label, "dev", args.interface])


def stop(args):
    print(f"Renaming {args.interface} to neutral name ...")

    ip_link(["set", args.interface, "down"])
    rename_to_neutral(args.interface, set_first_down=False)


def parse_eui48(addr):
    try:
        return EUI(addr, version=48, dialect=mac_unix_expanded)
    except AddrFormatError as ex:
        raise ValueError(ex)


def main():
    parser = argparse.ArgumentParser(prog="fc-netdev")
    subparsers = parser.add_subparsers(required=True, dest="command")

    start_parser = subparsers.add_parser(
        "start",
        help="Bring up and configure physical link with the correct name",
    )
    start_parser.set_defaults(func=start)
    start_parser.add_argument(
        "-F",
        "--no-flow-control",
        action="store_false",
        dest="flow_control",
        help="Disable flow control on the physical link",
    )
    start_parser.add_argument(
        "-l",
        "--label",
        dest="label",
        help="Add LABEL as alternative name for the physical link",
    )
    start_parser.add_argument(
        "interface",
        metavar="INTERFACE",
        help="Target name for the physical link",
    )
    start_parser.add_argument(
        "mac_address",
        metavar="MAC_ADDRESS",
        help="MAC address of the physical link",
    )
    start_parser.add_argument(
        "mtu",
        metavar="MTU",
        help="MTU of the physical link",
    )

    stop_parser = subparsers.add_parser(
        "stop",
        help="Deconfigure physical link and move it to a neutral name",
    )
    stop_parser.set_defaults(func=stop)
    stop_parser.add_argument(
        "interface",
        metavar="INTERFACE",
        help="Name of physical link to be deconfigured",
    )

    args = parser.parse_args()

    try:
        with interface_renaming_lock():
            args.func(args)
    except subprocess.CalledProcessError as ex:
        fatal(f"Exception while running command: {ex}")


if __name__ == "__main__":
    main()
