import ./make-test-python.nix ({ pkgs, ... }:
let

  makeAddress = idx: "192.168.42.${toString idx}";

  makeHost = idx: isRouter: { lib, pkgs, ... }: let
    vlans = [ idx (if idx == 4 then 1 else idx + 1)];
  in {
    imports = [ ../nixos ../nixos/roles ];
    services.telegraf.enable = false;
    virtualisation.vlans = vlans;
    networking = lib.mkForce {
      useDHCP = false;
        firewall.allowPing = true;
        firewall.checkReversePath = false;
        interfaces.eth1 = {};
        interfaces.eth2 = {};
        interfaces.underlay.ipv4.addresses = [
          { address = makeAddress idx; prefixLength = 32; }
        ];
        firewall.trustedInterfaces = [ "eth1" "eth2" ];
    };

    boot.kernel.sysctl."net.ipv4.conf.all.ip_forward" = 1;
    boot.extraModprobeConfig = "options dummy numdummies=0";
    boot.initrd.availableKernelModules = [ "dummy" ];

    systemd.services."network-link-properties-underlay" = rec {
      description = "Set up underlay loopback device";
      wantedBy = [ "network-addresses-underlay.service" "multi-user.target" ];
      before = wantedBy;
      path = [ pkgs.iproute2 ];
      script = "ip link add underlay type dummy";
      preStop = "ip link delete underlay";
      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = true;
    };

    services.frr = {
      zebra.enable = true;
      zebra.config = ''
          frr version 8.5.1
          frr defaults datacentre
          !
          route-map set-source-address permit 1
           set src ${makeAddress idx}
          exit
          !
          ip protocol bgp route-map set-source-address
      '';
      bfd.enable = true;
      bgp.enable = true;
      bgp.config = ''
          frr version 8.5.1
          frr defaults datacenter
          !
          router bgp 6500${toString idx}
           bgp router-id ${makeAddress idx}
           bgp bestpath as-path multipath-relax
           no bgp ebgp-requires-policy
           neighbor remotes peer-group
           neighbor remotes remote-as external
           neighbor remotes capability extended-nexthop
           neighbor remotes bfd
           neighbor eth1 interface peer-group remotes
           neighbor eth2 interface peer-group remotes
           !
           address-family ipv4 unicast
            redistribute connected
            neighbor remotes prefix-list accept-all in
            neighbor remotes prefix-list ${if isRouter then "accept-all" else "accept-self"} out
           exit-address-family
          !
          exit
          !
          ip prefix-list accept-self seq 1 permit ${makeAddress idx}/32
          !
          ip prefix-list accept-all seq 1 permit ${makeAddress 0}/24 le 32
      '';
    };
  };

in {
  name = "frr";
  nodes = {
    host1 = makeHost 1 false;
    switch1 = makeHost 2 true;
    host2 = makeHost 3 false;
    switch2 = makeHost 4 true;
  };

  testScript = ''
    start_all()
    all_vms = [host1, host2, switch1, switch2]
    for vm in all_vms:
        vm.wait_for_unit("network-online.target")

    for vm in all_vms:
        x = vm.succeed("vtysh -c 'show version'")
        print(x)

    with subtest("wait for multi-path BGP routes to appear"):
        for host, remote, peer_addr in [
            (host1, 3, ["203", "104"]),
            (host2, 1, ["303", "404"]),
        ]:
            for addr in peer_addr:
                host.wait_until_succeeds(
                    f"ip route show 192.168.42.{remote} | grep -F fe80::5054:ff:fe12:{addr}"
                )

    with subtest("check basic network reachability"):
        host1.succeed("ping -c1 192.168.42.3")
        host2.succeed("ping -c1 192.168.42.1")

    with subtest("check nexthop group sync for indirect routes after link loss"):
        # bug in (at least) 8.5.4: when a link goes down, nexthops pointing
        # to the faulty link are deleted and removed from nexthop groups
        # (for ecmp routes) by the kernel. when the link comes back up, frr
        # recreates the nexthops pointing to the link, but does not
        # correctly reinstall them into nexthop groups for indirect ecmp routes.

        # simulate link loss (e.g. hardware fluke) by simply setting the
        # link down.
        host1.succeed("ip link set eth1 down")
        host1.wait_until_succeeds("journalctl -u bgpd | grep -E 'eth1.*in vrf default Down'")
        host1.sleep(2)

        # recover from link loss event
        host1.succeed("ip link set eth1 up")
        host1.wait_until_succeeds("journalctl -u bgpd -n1 | grep -F 'End-of-RIB for IPv4 Unicast from eth1'")
        host1.sleep(5)

        out = host1.succeed("ip route show 192.168.42.3")
        print(out)

        host1.succeed("ip route show 192.168.42.3 | grep -F fe80::5054:ff:fe12:203")
        host1.succeed("ip route show 192.168.42.3 | grep -F fe80::5054:ff:fe12:104")

  '';
})
