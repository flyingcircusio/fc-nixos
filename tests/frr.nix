import ./make-test-python.nix ({ pkgs, ... }:
let

  makeSubnetAddress = net: idx: "192.168.${toString net}.${toString idx}";

  makeUnderlayAddress = makeSubnetAddress 42;

  baseConfig = { lib, ... }: {
    imports = [ ../nixos ../nixos/roles ];
    services.telegraf.enable = false;
    networking = {
      useDHCP = lib.mkForce false;
      firewall.allowPing = lib.mkForce true;
      firewall.checkReversePath = lib.mkForce false;
    };

    boot.kernel.sysctl."net.ipv4.conf.all.ip_forward" = 1;
    boot.extraModprobeConfig = "options dummy numdummies=0";
    boot.initrd.availableKernelModules = [ "dummy" ];
  };

  underlayLink = name: { ... }: {
    networking.interfaces."${name}" = {};
    networking.firewall.trustedInterfaces = [ name ];
    systemd.services."${name}-netdev" = {
      wantedBy = [ "network-setup.service" "multi-user.target" ];
      requires = [ "network-setup.service" ];
      script = ":";
      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = true;
    };
  };

  loopbackLink = address: { pkgs, ... }: {
    networking.interfaces.underlay.ipv4.addresses = [
      { address = address; prefixLength = 32; }
    ];
    systemd.services.underlay-netdev = rec {
      description = "Set up underlay loopback device";
      wantedBy = [ "network-setup.service" "multi-user.target" ];
      before = wantedBy;
      after = [ "network-pre.service" ];
      requires = [ "network-setup.service" ];
      path = [ pkgs.iproute2 ];
      script = "ip link add underlay type dummy";
      preStop = "ip link delete underlay";
      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = true;
    };
  };

  makeFrrHost = { idx, redistribute ? false, evpn ? false }: { lib, ... }:
    assert (idx > 0) && (idx <= 4);
    let
      vlans = [ idx (if idx == 4 then 1 else idx + 1) ];
      address = makeUnderlayAddress idx;
      export-filter = if redistribute
                      then "accept-all-routes"
                      else "accept-local-routes";
    in {
      imports = [
        baseConfig
        (underlayLink "eth1")
        (underlayLink "eth2")
        (loopbackLink address)
      ];

      virtualisation.vlans = vlans;

      services.frr = {
        zebra.enable = true;
        zebra.config = ''
          frr version 8.5.1
          frr defaults datacenter
          !
          route-map set-source-address permit 1
           set src ${address}
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
          router bgp ${toString (65000 + idx)}
           bgp router-id ${address}
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
            neighbor remotes route-map accept-all-routes in
            neighbor remotes route-map ${export-filter} out
           exit-address-family
           !
           ${lib.optionalString evpn ''
           address-family l2vpn evpn
            neighbor remotes activate
            neighbor remotes route-map accept-all-routes in
            neighbor remotes route-map ${export-filter} out
            advertise-all-vni
            advertise-svi-ip
           exit-address-family
           ''}
          !
          exit
          !
          bgp as-path access-list local-origin seq 1 permit ^$
          !
          route-map accept-local-routes permit 1
           match as-path local-origin
          exit
          !
          route-map accept-all-routes permit 1
          exit
          !
        '';
      };
    };

in {
  name = "frr";
  testCases = {
    regression-test = {
      name = "regression-test";
      nodes = {
        host1 = makeFrrHost { idx = 1; };
        switch1 = makeFrrHost { idx = 2; redistribute = true; };
        host2 = makeFrrHost { idx = 3; };
        switch2 = makeFrrHost { idx = 4; redistribute = true; };
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
    };
  };
})
