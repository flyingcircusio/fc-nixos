"""Model entities commonly found in DHCP configuration files."""


import collections
import itertools


class HostAddr(collections.namedtuple("HostAddr", "name vlan mac ip")):
    """Represent a single host interface address record."""

    __slots__ = ()


class Hosts(object):
    """Collection of HostAddr objects."""

    def __init__(self):
        """New new Hosts collection."""
        self.byip = {}
        self.byname = collections.defaultdict(list)

    def _check_host(self, host):
        """Perform basic sanity checks on `host` before it is added."""
        if host.ip.ip in self.byip:
            raise RuntimeError("duplicate IP address", host)
        if host.ip.ip in (host.ip.cidr[0], host.ip.cidr[-1]):
            raise RuntimeError(
                "cowardly refuse to add network or broadcast address", host
            )

    def add(self, host):
        """Add `host` to the collection."""
        self._check_host(host)
        self.byip[host.ip.ip] = host
        self.byname[host.name].append(host)
        return self

    def __iter__(self):
        """Iterate over groups of hostaddrs with the same hostname.

        Each generated item is a list of HostAddr objects. The
        sort order is stable between invocations.
        """
        for hostname in sorted(self.byname):
            yield sorted(self.byname[hostname])

    def iter_unique_mac(self):
        """Iterate over groups of hostaddrs but leave out MAC duplicates.

        Each generated item is a list of HostAddr objects which have the
        same host name. If there are several HostAddrs with the same MAC
        addresses, only the first one is yielded.
        """
        seen = set()

        def firsttime(host):
            if host.mac not in seen:
                seen.add(host.mac)
                return True
            else:
                return False

        for hostgroup in self:
            yield list(filter(firsttime, hostgroup))


class Subnet(object):
    """Represents a subnet."""

    def __init__(self, network, dynamic, hosts=None):
        self.network = network
        self.dynamic = dynamic
        self._hosts = hosts if hosts else []

    @property
    def hostaddrs(self):
        for host in self._hosts:
            for hostaddr in host:
                if hostaddr.ip in self.network:
                    yield hostaddr


class SharedNetwork(object):
    """Represents a collection of subnets on the same physical network."""

    def __init__(self):
        """New shared networks collection."""
        self.subnets = set()

    def register(self, subnet):
        """Register the network given by `subnet`."""
        self.subnets.add(subnet)

    def __iter__(self):
        """Iterate over all registered subnets."""
        return iter(sorted(self.subnets, key=lambda x: x.network))
