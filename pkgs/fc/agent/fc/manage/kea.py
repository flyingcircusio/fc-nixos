"""Create Kea configuration based on directory data."""

import argparse
import json
import sys

import fc.util.configfile
import fc.util.dhcp
import fc.util.directory
import netaddr


class ConfigRenderer(object):
    @staticmethod
    def get_class(ipversion):
        """Factory which generates suitable shared network formatter."""
        if ipversion == 4:
            return Config4Renderer
        elif ipversion == 6:
            return Config6Renderer
        else:
            raise NotImplementedError("unsupported IP version", ipversion)

    def render(self, ident_base):
        config = {}
        config["name"] = self.vlan
        config[self.subnet_keyword] = [
            # SharedNetwork iterator guarantees stable sort order
            self.render_subnet(subnet, ident)
            for ident, subnet in enumerate(self.shared_network, ident_base)
        ]

        return len(self.shared_network), config


class Config4Renderer(ConfigRenderer):
    subnet_keyword = "subnet4"

    def __init__(self, vlan, shared_network, _domain):
        self.vlan = vlan
        self.shared_network = shared_network

    def render_subnet(self, subnet, ident):
        reservations = []
        for host in subnet.hostaddrs_unique_mac:
            reservations.append(
                {
                    "hw-address": str(host.mac),
                    "ip-address": str(host.ip.ip),
                    "hostname": host.name,
                }
            )

        config = {}
        config["id"] = ident
        config["subnet"] = str(subnet.network)
        config["reservations"] = reservations
        config["option-data"] = [
            # the default router always gets the first IP address;
            # additionally provides NTP service
            {"name": name, "data": str(subnet.network.cidr[1])}
            for name in ["routers", "ntp-servers"]
        ]

        if subnet.dynamic:
            # calculate ranges available for dynamic allocation
            ranges = []
            range_start = subnet.network.cidr[4]  # floating gw + 2 routers
            hostaddrs = sorted(subnet.hostaddrs, key=lambda x: x.ip.ip)
            for hostaddr in hostaddrs:
                if hostaddr.ip.ip < subnet.network.cidr[4]:
                    continue
                range_end = hostaddr.ip.ip - 1
                if range_end >= range_start:
                    ranges.append((range_start, range_end))
                range_start = hostaddr.ip.ip + 1
            if range_start <= subnet.network.cidr[-2]:
                ranges.append((range_start, subnet.network.cidr[-2]))

            config["pools"] = [
                {"pool": f"{start} - {end}"} for start, end in ranges
            ]

        return config


class Config6Renderer(ConfigRenderer):
    subnet_keyword = "subnet6"

    def __init__(self, vlan, shared_network, domain):
        self.vlan = vlan
        self.shared_network = shared_network
        self.domain = domain

    def render_subnet(self, subnet, ident):
        reservations = []
        for host in subnet.hostaddrs_unique_mac:
            hostname = (
                f"{host.name}.{self.domain}" if self.domain else host.name
            )
            reservations.append(
                {
                    "hw-address": str(host.mac),
                    "ip-addresses": [str(host.ip.ip)],
                    "hostname": hostname,
                }
            )

        config = {}
        config["id"] = ident
        config["subnet"] = str(subnet.network)
        config["reservations"] = reservations

        if subnet.dynamic:
            # grab a random portion of address space
            range_ = netaddr.IPNetwork(
                (
                    (
                        subnet.network.cidr.ip
                        | netaddr.IPAddress("::d1c0:0:0:0")
                    ).value,
                    80,
                )
            )

            config["pools"] = [{"pool": str(range_)}]

        return config


class Kea(object):
    """Kea configuration generator.

    This class retrieves information about configured hosts from the
    directory and creates a Kea configuration segment representing
    that information.
    """

    def __init__(self, args):
        self.location = args.location
        self.ipversion = args.ipversion
        self.domain = args.domain
        self.directory = fc.util.directory.connect(ring="max")
        self.hosts = fc.util.dhcp.Hosts()
        self.requested_networks = args.network if args.network else None
        self.excluded_networks = args.exclude
        self.networks = {}

    def query_directory(self):
        # Query all networks and their subnet declarations
        vlans = self.directory.lookup_networks_details(
            self.location, self.ipversion
        )
        # Only retain explicitly requested networks
        if self.requested_networks:
            vlans = {
                vlan: networks
                for vlan, networks in vlans.items()
                if vlan in self.requested_networks
            }

        for vlan, networks in vlans.items():
            self.networks[vlan] = fc.util.dhcp.SharedNetwork()
            for network in networks:
                subnet = fc.util.dhcp.Subnet(
                    netaddr.IPNetwork(network["cidr"]),
                    network["dhcp"],
                    self.hosts,
                )
                self.networks[vlan].register(subnet)

        # Query all hosts
        for record in self.directory.list_nodes_addresses(
            self.location, "", self.ipversion
        ):
            if (
                self.requested_networks
                and record["vlan"] not in self.requested_networks
            ):
                continue

            mac = record["mac"]
            if not mac:
                print(
                    "{}/{}: no MAC address".format(
                        record["name"], record["vlan"]
                    ),
                    file=sys.stderr,
                )
                continue

            try:
                hostaddr = fc.util.dhcp.HostAddr(
                    record["name"],
                    record["vlan"],
                    netaddr.EUI(mac, dialect=netaddr.mac_unix_expanded),
                    netaddr.IPNetwork(record["ip"]),  # XXX: IPAddress?
                )
            except (KeyError, ValueError, netaddr.AddrFormatError) as exc:
                continue

            self.hosts.add(hostaddr)

    def render(self, output):
        network_configs = []
        render_class = ConfigRenderer.get_class(self.ipversion)

        idx = 1
        # sort networks by vlan name to avoid subnet identifiers being
        # renumbered
        for vlan in sorted(self.networks.keys()):
            if vlan in self.excluded_networks:
                continue
            shnet = self.networks[vlan]
            renderer = render_class(vlan, shnet, self.domain)
            count, cfg = renderer.render(idx)
            idx += count
            network_configs.append(cfg)

        config = {"shared-networks": network_configs}
        json.dump(config, output, indent=2)


def main():
    """Kea config generator main script."""

    parser = argparse.ArgumentParser(
        prog="fc-kea",
        description="""\
Generate Kea configuration. Query the directory for all hosts
configured for the given networks in LOCATION. Each network gets a
subnet declaration and each host gets a fixed-address entry in the
generated configuration file. By default, all networks in the location
are used, unless one or more networks are given as options.
""",
        epilog="""\
Returns 0 on success and 1 on error. If the --output option is
present, return 2 to signal the output file has been changed.
""",
    )

    address_family = parser.add_mutually_exclusive_group(required=True)
    address_family.add_argument(
        "-4",
        action="store_const",
        dest="ipversion",
        const=4,
        help="Generate configuration for DHCPv4",
    )
    address_family.add_argument(
        "-6",
        action="store_const",
        dest="ipversion",
        const=6,
        help="Generate configuration for DHCPv6",
    )

    parser.add_argument(
        "-o",
        "--output",
        metavar="FILE",
        default=None,
        help="Write configuration to FILE instead of stdout",
    )
    parser.add_argument(
        "-L",
        "--location",
        metavar="LOCATION",
        required=True,
        help="Generate configuration for location LOCATION",
    )
    parser.add_argument(
        "-n",
        "--network",
        metavar="NETWORK",
        default=[],
        action="append",
        help="Include hosts in NETWORK in the configuration (may be specified multiple times)",
    )
    parser.add_argument(
        "-e",
        "--exclude",
        metavar="NETWORK",
        default=[],
        action="append",
        help="Twinned network: do not generate subnet definition for NETWORK, but include host addresses within its subnets e.g. IPMI addresses (may be specified multiple times)",
    )
    parser.add_argument(
        "-d",
        "--domain",
        metavar="DOMAIN",
        default=None,
        help="Domain name to use as suffix for qualifying hostnames (only used in DHCPv6)",
    )

    args = parser.parse_args()

    changed = False
    kea = Kea(args)
    kea.query_directory()
    if args.output:
        conffile = fc.util.configfile.ConfigFile(args.output)
        kea.render(conffile)
        changed = conffile.commit()
    else:
        kea.render(sys.stdout)
    if changed:
        sys.exit(2)


if __name__ == "__main__":
    main()
