---
global_sync_id: "v1"
---

# Outbound connectivity from VMs { #outbound }

How outbound connectivity from a VM to external hosts outside of the
Flying Circus works depends on the network configuration for that VM:

- VMs can always connect to remote IPv6 destinations directly, as all
  VMs are assigned public IPv6 addresses.

- If a VM has a public IPv4 address, then it can connect to remote
  IPv4 destinations directly.

- If a VM does *not* have a public IPv4 address available, then we
  perform network address translation (NAT) on our site border
  routers, to ensure that a public address is used as the source
  address of connections outside of our network.

We use a fixed set of addresses as NAT source addresses for outbound
IPv4 connections in each location.

- **RZOB** (Production datacenter):
  - **185.105.253.74**
  - **185.105.253.72**
  - 195.62.112.82 (retired 2025-07-08)
  - 195.62.112.83 (retired 2025-07-08)
  - 195.62.112.90 (retired 2025-07-08)
  - 195.62.112.91 (retired 2025-07-08)

- **WHQ** (Backup and staging datacenter):
  - **185.105.255.3**
  - **185.105.255.21**
  - 213.187.81.2 (retired 2025-09-30)

!!! warning
    If you are using NAT to connect to outside machines **and** those outside machines
    use a firewall to filter traffic based on the source addresses, those need to be
    kept in sync over time.

    Our NAT addresses change rarely, however, it has happened in the past that we needed to
    quickly respond to technical incidents and had to change those addresses.

    So, to reduce the "mean time to recovery" in those situations, please remember to add
    appropriate monitoring that is included in our application-specific status pages so
    our team will be automatically alerted if an application breaks due to NAT issues.

    Additionally, those checks will detect other situations where your application relies
    on an outside service and will be helpful in many other cases as well.
