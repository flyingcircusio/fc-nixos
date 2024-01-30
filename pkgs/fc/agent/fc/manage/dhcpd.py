"""Create dhcpd configuration based on directory data."""


import optparse
import os.path as p
import sys

import fc.util.configfile
import fc.util.dhcp
import fc.util.directory
import netaddr


def include(files):
    """Get each readable include file into the output.

    For the sake of robustness, it is not an error to specify
    non-existent include files. This way, a "search path" of include
    files can be specified on the command line.
    """
    for includefile in files:
        try:
            with open(includefile, "rb") as f:
                yield f.read()
        except EnvironmentError:
            pass


class HostsFormatter(object):
    """Render HostAddr object as configuration snippet."""

    @classmethod
    def new(cls, ipversion, hosts):
        """Return formatter for `hosts`."""
        if ipversion == 4:
            return Hosts4Formatter(hosts)
        elif ipversion == 6:
            return Hosts6Formatter(hosts)
        raise NotImplementedError("no formatter for IP version", ipversion)

    def __init__(self, hosts):
        self.hosts = hosts

    def render_addr(self, ipaddr):
        raise NotImplementedError

    def render_host(self, hostid, host):
        return """\
host {0} {{
    hardware ethernet {1};
    {2};
    option host-name "{3}";
}}
""".format(
            hostid, host.mac, self.render_addr(host.ip), host.name
        )

    @staticmethod
    def choose_names(hostgroup):
        """Generate host ids for all hosts in `hostgroup`."""
        if len(hostgroup) == 1:
            yield hostgroup[0].name
            return
        i = 0
        for host in hostgroup:
            yield "{0}-{1}-{2}".format(host.name, host.vlan, i)
            i += 1

    def __str__(self):
        """Format a sequence of host records and return it as string."""
        out = []
        for hgroup in self.hosts.iter_unique_mac():
            out += [
                self.render_host(hid, host)
                for hid, host in zip(self.choose_names(hgroup), hgroup)
            ]
        return "\n".join(out)


class Hosts4Formatter(HostsFormatter):
    def render_addr(self, hostip):
        """IPv4 address statement."""
        return "fixed-address {0}".format(hostip.ip)


class Hosts6Formatter(HostsFormatter):
    def render_addr(self, hostip):
        """IPv6 address statement."""
        return "fixed-address6 {0}".format(hostip.ip)


class NetworkFormatter(object):
    """Render a shared network containing subnets as string."""

    @staticmethod
    def new(ipversion, sharednetwork, networkname, include_dir=None):
        """Factory that creates suitable shared network formatter.

        `ipversion` is the IP protocol version. `sharednetwork` is the
        SharedNetwork object that should be rendered. `networkname` is
        used as network identifier in the "shared-network" clause.
        """
        if ipversion == 4:
            return Network4Formatter(sharednetwork, networkname, include_dir)
        elif ipversion == 6:
            return Network6Formatter(sharednetwork, networkname, include_dir)
        raise NotImplementedError("unsupported IP version", ipversion)

    def __init__(self, sharednetwork, networkname, include_dir=None):
        self.sharednetwork = sharednetwork
        self.networkname = networkname
        self.include_dir = include_dir

    @property
    def local_include_file(self):
        return p.join(
            self.include_dir,
            "{}.{}.in".format(self.include_prefix, self.networkname),
        )

    def __str__(self):
        out = []
        if self.include_dir:
            try:
                with open(self.local_include_file) as f:
                    out += [
                        "# included from {}\n".format(self.local_include_file),
                        f.read() + "\n",
                    ]
                    return "".join(out)
            except EnvironmentError:
                pass
        out.append("shared-network {0} {{\n".format(self.networkname))
        out += [self.render_template(subnet) for subnet in self.sharednetwork]
        out.append("}\n\n")
        return "".join(out)


class Network4Formatter(NetworkFormatter):
    """IPv4-specific details of NetworkFormatter."""

    include_prefix = "dhcpd"

    def render_template(self, subnet):
        """Render IPv4 subnet clause."""
        return """\
    subnet {0} netmask {1} {{
{2}        option subnet-mask {1};
        option routers {3};
        authoritative;
    }}
""".format(
            subnet.network.ip,
            subnet.network.netmask,
            self._dynamicrange(subnet),
            self._router(subnet),
        )

    def _dynamicrange(self, subnet):
        """Address range that is availabe for dynamic allocation."""
        if not subnet.dynamic:
            return ""
        ranges = []
        range_start = subnet.network.cidr[4]
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
        return "".join("        range {0} {1};\n".format(*r) for r in ranges)

    def _router(self, subnet):
        """The default router always gets the first IP address."""
        return subnet.network.cidr[1]


class Network6Formatter(NetworkFormatter):
    """IPv6-specific details of NetworkFormatter."""

    include_prefix = "dhcpd6"

    def render_template(self, subnet):
        """Render IPv6 subnet6 clause."""
        return """\
    subnet6 {0} {{
{1}        authoritative;
    }}
""".format(
            subnet.network, self._dynamicrange(subnet)
        )

    def _dynamicrange(self, subnet):
        """Grab a random portion of the address space with 31331 name :-)"""
        if not subnet.dynamic:
            return ""
        return "        range6 {0};\n".format(
            netaddr.IPNetwork(
                (
                    (
                        subnet.network.cidr.ip
                        | netaddr.IPAddress("::d1c0:0:0:0")
                    ).value,
                    80,
                )
            )
        )


class DHCPd(object):
    """dhcpd.conf generator.

    This class retrieves information about configured hosts from the
    directory and creates a dhcpd.conf part that represents that
    information. This part can optionally be merged with one or more
    static includes to assemble a complete dhcpd.conf file.
    """

    def __init__(self, location, ipversion=4):
        """Initialize instance with location, vlan, and ipversion defaults."""
        self.location = location
        self.ipversion = ipversion
        self.directory = fc.util.directory.connect(ring="max")
        self.hosts = fc.util.dhcp.Hosts()
        self.networks = {}

    def query_directory(self):
        """Retrieve networks and hosts from directory and add them to subnets."""
        # Query all networks and their subnet declarations
        vlans = self.directory.lookup_networks_details(
            self.location, self.ipversion
        )
        for vlan, networks in list(vlans.items()):
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
            mac = record["mac"]

            if not mac:
                print(record["name"])
                continue

            try:
                hostaddr = fc.util.dhcp.HostAddr(
                    record["name"],
                    record["vlan"],
                    netaddr.EUI(mac, dialect=netaddr.mac_unix),
                    netaddr.IPNetwork(record["ip"]),
                )
            except (KeyError, ValueError, netaddr.AddrFormatError) as exc:
                # XXX Log this?
                continue

            self.hosts.add(hostaddr)

    def render(self, includes=None, inc_dir=None):
        """Assemble complete dhcpd.conf configuration file.

        `includes` is a list of static includes which are read in listed
        order. Includes that don't exist are silently skipped. Returns a
        StringIO object with the rendered configuration file.
        """
        out = ["# auto-generated by localconfig-dhcpd\n\n"]
        out += include(includes or [])
        out += [
            str(NetworkFormatter.new(self.ipversion, shnet, vlan, inc_dir))
            for vlan, shnet in sorted(self.networks.items())
        ]
        out.append(str(HostsFormatter.new(self.ipversion, self.hosts)))
        return "".join(out)


def process_options():
    """Set up and parse options for dhcpd.conf generator."""
    optp = optparse.OptionParser(
        usage="%prog [-4|-6] [-i INCLUDE] [-o OUTFILE] LOCATION",
        description="""\
Generate dhcpd.conf. Query gocept.directory for all networks and hosts
configured for LOCATION. Each network gets a subnet declaration and each
host gets a fixed-address entry in the generated dhcpd.conf file.
""",
        epilog="""\
Return 0 on success and 1 on error. If the --output option is present,
return 2 to signal the the output file has been changed.""",
    )
    optp.add_option(
        "-4",
        action="store_const",
        dest="ipversion",
        const=4,
        default=4,
        help="generate configuration for DHCPv4 (default)",
    )
    optp.add_option(
        "-6",
        action="store_const",
        dest="ipversion",
        const=6,
        help="generate configuration for DHCPv6",
    )
    optp.add_option(
        "-i",
        "--include",
        metavar="FILE",
        action="append",
        default=[],
        help="include static file at the beginning of the "
        "configuration; option may be given multiple times",
    )
    optp.add_option(
        "-l",
        "--local-include-dir",
        metavar="DIR",
        default=None,
        help="look up override files for specific networks in this "
        "directory (format: dhcp{,6}.${vlan}.in)",
    )
    optp.add_option(
        "-o",
        "--output",
        metavar="FILE",
        default=None,
        help="write configuration to FILE instead of stdout",
    )
    options, args = optp.parse_args()
    if len(args) < 1:
        optp.error("no LOCATION given")
    return options, args[0]


def main():
    """dhcpd.conf generator main script."""
    options, location = process_options()
    changed = False
    dhcpd = DHCPd(location, options.ipversion)
    dhcpd.query_directory()
    if options.output:
        conffile = fc.util.configfile.ConfigFile(options.output)
        conffile.write(dhcpd.render(options.include, options.local_include_dir))
        changed = conffile.commit()
    else:
        sys.stdout.write(dhcpd.render(options.include))
    if changed:
        sys.exit(2)


if __name__ == "__main__":
    main()
