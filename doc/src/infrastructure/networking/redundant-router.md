---
global_sync_id: "v1"
---

# Redundant router

Routers are an important resource within a location because they provide all
external connectivity for all machines to the internet.

From our upstream providers we expect a reliability of at least 99,9% on each
link and with redundant uplinks we expect an overall reliability of 99,99% on
our upstream connectivity.

To improve the availability of our own routers without expensive
high-availability hardware we use a redundant setup where two machines run
an identical setup and can fail-over in a primary/secondary mode.

Our goal is to be able to guarantee a recovery of connectivity within
less than 4 hours.

## Configuration details: BGP-based

In locations that support it (currently: DEV, RZOB) we leverage BGP as a
mechanism to dynamically provide fail-over capabilities between our routers
and the uplink routers.

In this case the TR vlan does not have a fixed gateway address but retrieves
this information dynamically from a BGP session with our provider.

All the internal VLANs (mgm, srv, fe) are configured on each router with a
static regular IP in addition to the gateway IP which is a "floating" address
and gets automatically assigned by the fail-over mechanism.

The gateway addresses of the IP networks in this location are assigned to a
physical host in the directory that is not a real puppet client but a
placeholder node. It is called \<location-router> (e.g. "whq-router" for
the router in our WHQ network).

The routers within our location use VRRP
(<https://de.wikipedia.org/wiki/Virtual_Router_Redundancy_Protocol>) to decide
which router should be the master. They leverage interface status information as
well as default route availability.

When the primary/secondary switches then we also enable/disable the DHCPD and
RADVD services accordingly.

## Configuration details: Non-BGP

For locations that do not have BGP available from our providers (currently: WHQ
and some customer-owned locations) we extend the VRRP configuration to the TR
vlan and use a floating gateway IP there as well.

This is an older setup that does have some impact on availability under certain
circumstances on the provide side and is less flexible from our side.

## Manually switching master/backup routers

The master/backup role is normally automatically determined by an election
process between all possible routers.

If for some reason, this should be manually changed, then the following steps
need ot be performed:

- locate the current master and log in per SSH
- disable the keepalive daemon by calling `/etc/init.d/keepalived stop`
  (alternatively the daemon can be restarted)

## Known issues

### Inertia

Switching between routers back and forth quickly can cause visible customer
outages as the process will cause some packets to be lost and BGP sessions to
reconverge.

### Uplink router ARP caching

In locations that use VRRP on the TR vlan there may be additional delays  if the
upstream routers should cache our routers' MAC addresses and ignore the MAC
updates we are sending proactively. This will converge within at most a few
minutes.
