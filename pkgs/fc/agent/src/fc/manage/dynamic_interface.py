"""Management of dynamic guest interfaces."""

import json
import re
import shutil
import sys
from pathlib import Path
from subprocess import check_call, check_output
from typing import Annotated, Any, NamedTuple, Optional, Tuple

import structlog
import yaml
from netaddr.ip import IPAddress
from typer import Argument, Option

from fc.util.lock import locked
from fc.util.logging import init_logging
from fc.util.typer_utils import FCTyperApp

QEMU_CONFIG_DIR = Path("/etc/qemu/vm")
QEMU_ALTNAME_PATTERN = r"fcqemu-vm-(?P<id>[0-9]+)-net-(?P<net>[0-9]+)"

VXLAN_PORT = 4789

app = FCTyperApp("fc-dynamic-interface")
log = structlog.get_logger()


def json_cmd(*args, **kwargs):
    data = check_output(*args, **kwargs)
    return json.loads(data.decode("utf-8"))


def resolve_guest_from_altnames(iface: str) -> Tuple[int, int]:
    """Attempt to read metadata from VM interface altnames."""
    iface_data = json_cmd(["ip", "-j", "link", "show", "dev", iface])

    assert len(iface_data) == 1
    iface_data = iface_data[0]
    assert iface_data["ifname"] == iface

    for altname in iface_data.get("altnames", []):
        result = re.fullmatch(QEMU_ALTNAME_PATTERN, altname)
        if not result:
            continue
        entries = result.groupdict()

        vm_id = int(entries["id"])
        net_id = int(entries["net"])
        return (vm_id, net_id)

    raise ValueError(
        f"Could not infer VM and network from altnames on interface: {iface}"
    )


def resolve_guest_enc(vm_id: int) -> dict[str, Any]:
    """Resolve a VM to its ENC data from the VM ID"""
    for candidate in QEMU_CONFIG_DIR.glob("*.cfg"):
        with candidate.open() as f:
            cfg = yaml.safe_load(f)
            if cfg["parameters"]["id"] == vm_id:
                return cfg

    raise ValueError(f"Could not find ENC data for VM with ID: {vm_id}")


def resolve_network_name(net_id: int, cfg: dict[str, Any]) -> str:
    networks = cfg["parameters"]["interfaces"]

    for net, net_config in networks.items():
        if (
            net_config.get("network_number") == net_id
            and net_config.get("linktype") == "dynamic"
        ):
            return net

    raise ValueError(
        f"Could not find dynamic network in guest ENC with ID: {net_id}"
    )


def resolve_network(iface: str) -> Tuple[str, int]:
    vm_id, net_id = resolve_guest_from_altnames(iface)
    cfg = resolve_guest_enc(vm_id)
    net = resolve_network_name(net_id, cfg)

    return net, net_id


def list_all_interfaces() -> list[dict[str, Any]]:
    # detailed output required for link info
    return json_cmd(["ip", "-d", "-j", "link", "show"])


class Context(NamedTuple):
    lock_dir: Path


context: Context


@app.callback(no_args_is_help=True)
def fc_dynamic_interface(
    verbose: bool = Option(
        False,
        "--verbose",
        "-v",
        help="Show debug messages and code locations.",
    ),
    lock_dir: Path = Option(
        file_okay=False,
        default="/run/lock",
        help="Directory for lock files for exclusive operations.",
    ),
):
    global context
    init_logging(verbose, syslog_identifier="fc-dynamic-interfaces")
    context = Context(lock_dir)
    iproute2 = shutil.which("ip")
    if not iproute2:
        log.error("Could not find 'ip' binary in PATH")
        sys.exit(1)


def parse_ipaddress(address: str) -> Optional[IPAddress]:
    try:
        return IPAddress(address)
    except:
        return None


@app.command(name="attach")
def attach_interface(
    interface: str,
    vtep_address: Annotated[IPAddress, Argument(parser=parse_ipaddress)],
):
    """Attach the dynamic guest interface.

    Attach the dynamic guest interface to the corresponding bridge
    interface, creating the bridge and VXLAN interfaces if
    necessary.
    """

    net, net_id = resolve_network(interface)
    bridge = f"br{net}"
    vxlan = f"vx{net}"

    with locked(log, context.lock_dir, "dynamic_interfaces.lock"):
        ifaces = list_all_interfaces()

        bridge_exists = False
        for iface in ifaces:
            if iface["ifname"] != bridge:
                continue
            if (
                "linkinfo" in iface
                and iface["linkinfo"].get("info_kind") != "bridge"
            ):
                raise ValueError(
                    f"Interface {iface['ifname']} is not a bridge interface, aborting!"
                )
            bridge_exists = True
            break

        if not bridge_exists:
            # create and configure vxlan device
            check_call(
                [
                    "ip",
                    "link",
                    "add",
                    vxlan,
                    "type",
                    "vxlan",
                    "id",
                    str(net_id),
                    "local",
                    str(vtep_address),
                    "dstport",
                    str(VXLAN_PORT),
                    "nolearning",
                ]
            )
            check_call(["ip", "link", "set", vxlan, "addrgenmode", "none"])

            # create bridge interface
            check_call(["ip", "link", "add", bridge, "type", "bridge"])

            # attach vxlan to bridge interface and set parameters
            check_call(["ip", "link", "set", vxlan, "master", bridge])
            check_call(
                [
                    "ip",
                    "link",
                    "set",
                    vxlan,
                    "type",
                    "bridge_slave",
                    "learning",
                    "off",
                    "neigh_suppress",
                    "on",
                ]
            )

            # set interfaces up
            check_call(["ip", "link", "set", vxlan, "up"])
            check_call(["ip", "link", "set", bridge, "up"])

        # attach guest interface to bridge
        check_call(["ip", "link", "set", interface, "master", bridge])

    # set guest interface up
    check_call(["ip", "link", "set", interface, "up"])


@app.command(name="detach")
def detach_interface(interface: str):
    """Detach the dynamic guest interface.

    If the corresponding bridge interface has no further child
    interfaces, then delete it and the associated VXLAN interface.
    """

    net, net_id = resolve_network(interface)
    bridge = f"br{net}"
    vxlan = f"vx{net}"

    with locked(log, context.lock_dir, "dynamic_interfaces.lock"):
        check_call(["ip", "link", "set", interface, "nomaster"])

        # XXX: delete guest iface here too?

        ifaces = list_all_interfaces()
        remaining = []
        for iface in ifaces:
            if iface["ifname"] != vxlan and iface.get("master") == bridge:
                remaining.append(iface)

        if remaining:
            return

        check_call(["ip", "link", "delete", vxlan])
        check_call(["ip", "link", "delete", bridge])


if __name__ == "__main__":
    app()
