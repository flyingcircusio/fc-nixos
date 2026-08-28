---
global_sync_id: "v1"
---

% last review: 2026-05-07

% review schedule: 1 year

% ISMSControl: 8.20
% ISMSControl: 8.21
% ISMSControl: 8.22

# Network security { #network-security }

Network security is handled on different levels depending on the class of
traffic. The different classes are separated by harmonized use of
virtualisation techniques (VLANs, VXLANs) and protected from internet traffic
by firewalls on the routers in a Flying Circus location as well as individually
on every node (physical hosts and virtual machines).

## Network classes and router firewalls

### Frontend network (fe)

Nodes providing services intended for the general public (users of applications
hosted within the Flying Circus) have one or more IPv4/IPv6 addresses in this
network. Nodes not intended to provide services to the internet are not
assigned addresses on this network.

Traffic to addresses in this network is forwarded by the router firewall
without limitations.

The node firewalls block traffic on this network by default. Opening up ports to
expose services to the internet happens as needed using our configuration
management.

### Server network (srv)

All nodes have IP addresses in the server network. This is used by applications
for internal communication, e.g. application servers communicating with their
database or a load balancer communicating with the application servers.

Nodes on the server network generally use private IPv4 addresses and public IPv6
addresses. Older machines may use public IPv4 addresses for historic reasons.
Outbound traffic is generally allowed and IPv4 traffic will be masqueraded on
the gateway firewall. If a machine needs unmasqueraded IPv4 access to the
internet, customers need to provision a public IPv4 address on the frontend
network.

Inbound traffic to the SRV network will be blocked on the gateway firewall with
the following exceptions:

- ICMP
- 22/tcp (ssh)
- 8140/tcp (puppet)

Port 8140 is only supported for historic reasons and not used on our NixOS
platform. The firewall exception for this port will be removed in the future.

### Storage network (sto and stb)

These networks are used for storage traffic (Ceph RBD for KVM hosts and backup
servers as well as S3-compatible storage via the Rados Gateway). They are only
accessible to ring 0 machines owned by the Flying Circus but not customer-owned
equipment or virtual machines. Customer-owned environments implement separate
storage networks.

This network uses private IPv4 addresses that are not routed from the internet.
Traffic from outside this network is not forwarded.

### Management network (mgm)

This network is used for management purposes only: access to base management
controllers (IPMI), switch consoles, machine OSes etc.

It uses private IPv4 addresses that are not routed from the internet. Traffic
from outside this network is not allowed.

### Underlay network (ul)

This network is used to implement a redundant, dynamic BGP/EVPN/VXLAN
environment to transport all other networks as needed to physical machines.

It uses a private IPv4 network as well as IPv6 link local addresses. The
underlay is only accessible to ring 0 machines owned by the Flying Circus but
not customer-owned equipment or virtual machines. Customer-owned environments
implement separate underlay networks.

### Access network (access)

This network is used to provide network and internet connectivity for machines
that are not able to participate in our management scheme. Machines on this
network are  allowed to access the internet and frontend network but are not
allowed to access any of our other internal networks. 

## Per-node firewalls

Every node is running an additional local firewall using iptables and will by
default

* block all traffic to the frontend IPs, except when explicitly opened by a
  configured service, and
* block all traffic to the server-to-server IPs, except for VMs from the same
  resource group.
