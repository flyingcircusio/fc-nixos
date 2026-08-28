---
global_sync_id: "v1"
---

# Connecting to VMs { #connecting }

Generally you can connect to VMs on their "SRV" interface from the outside by calling:

```
$ ssh myvm00.fcio.net
Last login: Wed Feb 19 14:54:07 CET 2014 from 89.204.138.251 on pts/0
Welcome to the Flying Circus!
```

However, due to a shortage of IPv4 addresses and an unpredictable status of
IPv6 deployments, this might not work out of the box. Let's go through a
couple of options you have, if the example above does not work out of the box.

## Getting an overview of your situation

**VM has a public IPv4 address on SRV**:

```
$ ping myvm00.fcio.net
PING myvm00.fcio.net (212.122.41.186): 56 data bytes
64 bytes from 212.122.41.186: icmp_seq=0 ttl=57 time=29.110 ms
64 bytes from 212.122.41.186: icmp_seq=1 ttl=57 time=25.364 ms
^C
--- myvm00.fcio.net ping statistics ---
2 packets transmitted, 2 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 25.364/27.237/29.110/1.873 ms
```

**VM has a private IPv4 address on SRV**:

```
$ ping myvm00.fcio.net
ping: cannot resolve myvm00.fcio.net: Unknown host
```

**VM is accessible through IPv6**:

```
$ ping6 myvm00.fcio.net
PING6(56=40+8+8 bytes) 2002:5e87:9a92:1:687c:1601:8692:c1e9 --> 2a02:238:f030:103::1d
16 bytes from 2a02:238:f030:103::1d, icmp_seq=0 hlim=59 time=27.642 ms
16 bytes from 2a02:238:f030:103::1d, icmp_seq=1 hlim=59 time=26.238 ms
16 bytes from 2a02:238:f030:103::1d, icmp_seq=2 hlim=59 time=25.941 ms
^C
--- myvm00.fcio.net ping6 statistics ---
3 packets transmitted, 3 packets received, 0.0% packet loss
round-trip min/avg/max/std-dev = 25.941/26.607/27.642/0.742 ms
```

**VM is not accessible through IPv6**:

```
$ ping6 myvm00.fcio.net
ping6: UDP connect: No route to host
```

!!! note
    If you get a result that isn't shown here, please contact our support and we'll amend this list.

## VM has a public IPv4 address

Everything should be fine: independently of whether your ISP provides you with
IPv4 and/or IPv6  you should be able to connect. If not: please contact our
support.

## VM has a private IPV4 address but you have native IPv6 from your ISP

Excellent! You should be able to connect as IPv6 will automatically pick up
where IPv4 dropped the ball. If you can not connect in this scenario: please
contact our support.

## VM has a private IPv4 and you do not have native IPv6

This is the tricky part: the VM is only accessible via IPv6 directly from the
outside but you don't have it yet.

### Using an IPv4 SSH jump host { #jumphost }

SSH can perform complex connection setups including proxying through other
machines. Fortunately there will always be at least one public IPv4 address
that is accessible to you and you can use this to connect to the machine you
actually want to go to.

Put the following in your `~/.ssh/config` to enable transparent SSH jump
hosts:

```
Host fcio-jumphost
  Hostname <VMNAME>.fe.rzob.ipv4.gocept.net

Host *.gocept.net
  User <USERNAME>
  ProxyJump fcio-jumphost

Host *.fcio.net
  User <USERNAME>
  ProxyJump fcio-jumphost
```

Remember to replace \<VMNAME> with the name of a VM that has a public frontend
IPv4 address configured. It doesn't matter which other VM you connect to. Also,
replace \<USERNAME> with the unix username that you are using in the Flying
Circus.


If you have an older SSH that doesn't yet support the `ProxyJump`

```
Host *.gocept.net
    User <USERNAME>
    ProxyCommand ssh flyingcircus-jump-host -W %h:%p

Host *.fcio.net
    User <USERNAME>
    ProxyCommand ssh flyingcircus-jump-host -W %h:%p

Host flyingcircus-jump-host
    HostName <VMNAME>.fe.rzob.ipv4.gocept.net
    User <USERNAME>
    ProxyCommand none
```


### Using a private OpenVPN server

If a project has an OpenVPN server available (`external_net`
role), tunneling through a VPN connection may be a convenient alternative.

### Using IPv6 rapid deployment options

Even if your provider does not provide you with IPv6 there is a good chance you
can easily get IPv6 with one of the following "rapid deployment" options.

The technologies we recommend are:

- [6to4](https://en.wikipedia.org/wiki/6to4) which works in many cases and is
  supported by Linux, Windows, Mac OS X and many routers. You can often turn
  this on for your whole office network by simply setting an "Enable 6to4"
  option in your router.
- [Teredo tunneling](https://en.wikipedia.org/wiki/Teredo_tunneling) may be a last-resort
  option that can be configured on individual machines and is supported on Windows and Linux.
- Traditional IP tunnels, like provided by [Tunnelbroker](https://tunnelbroker.net/)
  are also an option, although their performance and reliability varies.

## Further support

IPv6 deployment is gaining traction but the rapid deployment options are
unreliable at times. Check above options or let us know if you found a solution
that worked better for you. If you struggle, please contact our support: we're
here to help you through the hard times of IPv4 exhaustion!
