import argparse
import ipaddress
import socket
import subprocess
import sys

import fc.util.configfile
import fc.util.directory


def main():
    parser = argparse.ArgumentParser(
        prog="fc-kresd-rfc1918",
        description="Generate kresd hosts file for private IPv4 addresses",
    )
    parser.add_argument(
        "-o",
        "--output",
        metavar="FILE",
        default=None,
        help="Write configuration to FILE instead of stdout",
    )
    parser.add_argument(
        "-s",
        "--suffix",
        metavar="ZONE",
        default="gocept.net",
        help="Use ZONE as the domain name suffix",
    )
    parser.add_argument(
        "-r",
        "--reload-kresd",
        action="store_true",
        default=False,
        help="Send SIGHUP to all running kresd instances to reload the hosts file",
    )

    if not socket.getdefaulttimeout():
        socket.setdefaulttimeout(60)

    args = parser.parse_args()
    directory = fc.util.directory.connect(ring="max")

    entries = []
    for node in sorted(directory.list_nodes(), key=lambda n: n["name"]):
        shortname = node["name"]
        params = node["parameters"]
        location = params["location"]

        canonical_vlan = None
        vlans = set(params["interfaces"])
        for v in ["srv", "mgm"]:
            if v in vlans:
                canonical_vlan = v
                break

        for vlan, iface in sorted(params["interfaces"].items()):
            for addresses in sorted(iface["networks"].values()):
                for address in sorted(addresses):
                    addr = ipaddress.ip_address(address)
                    if addr.version != 4 or not addr.is_private:
                        continue

                    # custom reverse dns configured on private
                    # addresses is ignored.
                    entries.append(
                        (
                            shortname,
                            vlan,
                            location,
                            addr,
                            vlan == canonical_vlan,
                        )
                    )

    if args.output:
        handle = fc.util.configfile.ConfigFile(args.output)
    else:
        handle = sys.stdout

    for name, vlan, loc, addr, canonical in entries:
        if canonical:
            fqdn = f"{name}.{args.suffix}"
        else:
            fqdn = f"{name}.{vlan}.{location}.{args.suffix}"

        print(f"{addr} {fqdn}", file=handle)

    if args.output:
        changed = handle.commit()
        if changed and args.reload_kresd:
            print(
                "info: reloading kresd instances after hosts file changed",
                file=sys.stderr,
            )
            proc = subprocess.run(
                ["systemctl", "kill", "--signal=SIGHUP", "kresd@*"]
            )
            if proc.returncode != 0:
                print(
                    "error: could not reload kresd instances using systemd",
                    file=sys.stderr,
                )
                sys.exit(1)


if __name__ == "__main__":
    main()
