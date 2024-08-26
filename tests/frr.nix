import ./make-test-python.nix ({ pkgs, ... }:
let

  makeSubnetAddress = net: idx: "192.168.${toString net}.${toString idx}";

  makeUnderlayAddress = makeSubnetAddress 42;
  makeOverlayHostAddress = makeSubnetAddress 23;
  makeOverlayTapAddress = idx: makeSubnetAddress 23 (idx + 100);

  makePrivateMac = scope: idx: "06:00:00:00:${scope}:0${toString idx}";
  makeHostMac = makePrivateMac "42";
  makeTapMac = makePrivateMac "23";

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

  underlayLink = name: { lib, ... }: {
    networking.interfaces."${name}".ipv4.addresses = lib.mkForce [];
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

  tapLink = name: { ... }: {
    networking.interfaces."${name}" = {
      virtual = true;
      virtualType = "tap";
    };
  };

  bridgeLink = mac: address: children: { ... }: {
    networking.bridges.br0.interfaces = children;
    networking.interfaces.br0 = {
      macAddress = mac;
      ipv4.addresses = [
        { address = address; prefixLength = 24; }
      ];
    };
  };

  vxlanLink = mac: vtepAddr: { pkgs, ... }: {
    networking.interfaces.vxlan0 = {};
    systemd.services.vxlan0-netdev = rec {
      description = "Set up overlay VXLAN device";
      wantedBy = [ "network-setup.service" "multi-user.target" ];
      before = wantedBy;
      after = [ "network-pre.service" ];
      requires = [ "network-setup.service" ];
      path = [ pkgs.iproute2 ];
      script = ''
        ip link add vxlan0 type vxlan \
          id 23 local ${vtepAddr} \
          dstport 4789 nolearning

        ip link set vxlan0 address ${mac}
        ip link set vxlan0 mtu 1280
        ip link set vxlan0 addrgenmode none
      '';
      preStop = ''
        ip link delete vxlan0
      '';
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

  makeEvpnHost = { idx, taps }: { pkgs, lib, ... }:
    let
      underlayAddr = makeUnderlayAddress idx;
      bridgeMac = makeHostMac idx;
      tapByName = builtins.listToAttrs
        ((lib.imap0 (i: v: lib.nameValuePair "tap${toString i}" v)) taps);

      makePingService = iface: tapidx: let
        ipaddr = makeOverlayTapAddress tapidx;
        macaddr = makeTapMac tapidx;
      in lib.nameValuePair "ping-${iface}" (rec {
        description = "Respond to ping and arp on ${iface}";
        wantedBy = [ "multi-user.target" ];
        requires = [ "network-addresses-${iface}.service" ];
        after = requires;
        serviceConfig.ExecStart = "${pkgs.fc.ping-on-tap}/bin/ping-on-tap ${iface} ${macaddr} ${ipaddr}";
      });

    in {
      imports = [
        (makeFrrHost { inherit idx; evpn = true; })
        (vxlanLink bridgeMac underlayAddr)
        (bridgeLink bridgeMac
          (makeOverlayHostAddress idx)
          ([ "vxlan0" ] ++ (builtins.attrNames tapByName))
        )
      ] ++
      (builtins.map (n: tapLink n) (builtins.attrNames tapByName));

      environment.systemPackages = [ pkgs.fc.check-rib-integrity ];

      systemd.services = lib.mapAttrs' makePingService tapByName;
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
    evpn = {
      name = "evpn";
      nodes = {
        host1 = makeEvpnHost { idx = 1; taps = [ 1 2 ]; };
        switch1 = makeFrrHost { idx = 2; redistribute = true; evpn = true; };
        host2 = makeEvpnHost { idx = 3; taps = [ 3 4 ]; };
        switch2 = makeFrrHost { idx = 4; redistribute = true; evpn = true; };
      };

      testScript = ''
        start_all()
        all_vms = [host1, host2, switch1, switch2]
        for vm in all_vms:
            vm.wait_for_unit("network-online.target")

        for vm in all_vms:
            x = vm.succeed("vtysh -c 'show version'")

        with subtest("wait for local tap MAC addresses to appear"):
            for host, addrs in [
                (host1, ["06:00:00:00:23:01", "06:00:00:00:23:02"]),
                (host2, ["06:00:00:00:23:03", "06:00:00:00:23:04"]),
            ]:
                for addr in addrs:
                    host.wait_until_succeeds(
                        f"bridge fdb show br br0 | grep -F {addr}"
                    )

        with subtest("wait for remote tap MAC addresses to appear"):
            for host, addrs in [
                (host1, ["06:00:00:00:42:03", "06:00:00:00:23:03", "06:00:00:00:23:04"]),
                (host2, ["06:00:00:00:42:01", "06:00:00:00:23:01", "06:00:00:00:23:02"]),
            ]:
                for addr in addrs:
                    host.wait_until_succeeds(
                        f"bridge fdb show br br0 | grep -F {addr}"
                    )

        with subtest("check evpn network reachability"):
            with subtest("checking SVI addresses are reachable"):
                host1.succeed("ping -c1 192.168.23.3")
                host2.succeed("ping -c1 192.168.23.1")
            with subtest("checking remote tap device responders are reachable"):
                for host, addrs in [
                    (host1, ["192.168.23.103", "192.168.23.104"]),
                    (host2, ["192.168.23.101", "192.168.23.102"]),
                ]:
                    for addr in addrs:
                        # send multiple pings in case ping-on-tap gets stuck
                        host.succeed(f"ping -A -c5 {addr}")

        with subtest("rib and fib should not have mismatches"):
            for host in [host1, host2]:
                host.succeed("check_rib_integrity check-unicast-rib -p 192.168.42.0/24")
                host.succeed("check_rib_integrity check-evpn-rib -n 23")

        with subtest("check script should detect ipv4 rib mismatches"):
            # monitoring script should detect extra addresses in the kernel
            # not in the rib
            host1.succeed(
                "ip route add 192.168.42.100/32 dev eth1 "
                "via inet6 fe80::1 proto bgp"
            )

            code, output = host1.execute("check_rib_integrity check-unicast-rib -p 192.168.42.0/24")
            assert code == 2, "Check script does not have CRITICAL status"
            print(output)

            host1.succeed("ip route del 192.168.42.100/32")
            host1.wait_until_succeeds("check_rib_integrity check-unicast-rib -p 192.168.42.0/24")

            # purposefully corrupt the rib in ways which frr doesn't
            # automatically detect.
            host1.succeed("ip route replace unreachable 192.168.42.3")
            host1.succeed(
                "ip route replace 192.168.42.3/32 proto bgp "
                "nexthop via inet6 fe80::5054:ff:fe12:203 dev eth2 "
                "nexthop via inet6 fe80::5054:ff:fe12:104 dev eth1 "
                "nexthop via inet6 fe80::1 dev eth1"
            )

            code, output = host1.execute("check_rib_integrity check-unicast-rib -p 192.168.42.0/24")
            assert code == 2, "Check script does not have CRITICAL status"
            print(output)

            # allow frr to reset the fib automatically
            host1.succeed("ip route del 192.168.42.3/32")
            host1.wait_until_succeeds("check_rib_integrity check-unicast-rib -p 192.168.42.0/24")

        with subtest("check script should detect evpn rib mismatches"):
            # monitoring script should detect extra entries in the macfdb
            # not in the rib
            host1.succeed(
                "bridge fdb add 06:00:00:00:23:ff dev vxlan0 "
                "dst 192.168.42.100 extern_learn dynamic"
            )
            host1.succeed(
                "bridge fdb add 06:00:00:00:23:ff dev vxlan0 "
                "extern_learn master"
            )

            code, output = host1.execute("check_rib_integrity check-evpn-rib -n 23")
            assert code == 2, "Check script does not have CRITICAL status"
            print(output)

            host1.succeed("bridge fdb del 06:00:00:00:23:ff dev vxlan0")
            host1.wait_until_succeeds("check_rib_integrity check-evpn-rib -n 23")


            # purposefully corrupt the rib in ways which frr doesn't
            # automatically detect
            host1.succeed(
                "bridge fdb replace 06:00:00:00:23:03 dev vxlan0 "
                "dst 192.168.42.100 extern_learn dynamic"
            )

            code, output = host1.execute("check_rib_integrity check-evpn-rib -n 23")
            assert code == 2, "Check script does not have CRITICAL status"
            print(output)

            # allow frr to reset the fib automatically
            host1.succeed("bridge fdb del 06:00:00:00:23:03 dev vxlan0")
            host1.wait_until_succeeds("check_rib_integrity check-evpn-rib -n 23")
      '';
    };
  };
})
