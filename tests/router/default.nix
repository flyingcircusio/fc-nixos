import ../make-test-python.nix (
  {
    testlib,
    pkgs,
    lib,
    ...
  }:

  with testlib;

  let
    makeRouterConfig =
      { id }:
      {
        config,
        pkgs,
        lib,
        ...
      }:
      let
        inherit (config) fclib;
      in
      {
        virtualisation.vlans = with config.flyingcircus.static.vlanIds; [
          mgm
          fe
          srv
          tr
        ];
        virtualisation.memorySize = 2048;

        imports = [
          ../../nixos
          ../../nixos/roles
        ];

        flyingcircus.roles.router = {
          enable = true;
          routerUplinkNetworks = [ "tr" ];

          birdConfig = builtins.readFile ./bird.conf;
          routerId = builtins.head fclib.network.tr.v4.addresses;

          keepalivedConfig = builtins.readFile ./keepalived.conf;

          zoneGeneratorConfig = "";
          # minimal test config
          bindConfig = ''
            acl "gocept.net" {
                127.0.0.0/8;
                ::/64;
                ${lib.concatStringsSep "\n" (map (n: "    ${n};") fclib.networks.all)}
            };

            options {
              directory "/var/cache/named";
              pid-file "/run/named/named.pid";

              listen-on-v6 { any; };
              allow-query { any; };
              allow-query-cache { "gocept.net"; };
              allow-recursion { "gocept.net"; };
              allow-transfer { "gocept.net"; };
              allow-update { none; };

              dnssec-validation auto;
            };

            include "/etc/bind/rndc.key";
            controls {
              inet 127.0.0.1 port 953 allow { 127.0.0.1/32; ::1/128; } keys { "rndc-key"; };
            };

            view "internal" {
              match-clients { "gocept.net"; };
              include "/etc/bind/internal-zones.conf";

              zone "localhost" IN {
                type master;
                file "/etc/bind/pri/localhost.zone";
                allow-update { none; };
                notify no;
              };

              zone "127.in-addr.arpa" IN {
                type master;
                file "/etc/bind/pri/127.zone";
                notify no;
              };
            };

            view "external" {
              match-clients { any; };
              include "/etc/bind/external-zones.conf";
            };
          '';
        };

        environment.etc."networks/tr".source = pkgs.writers.writeJSON "tr" fclib.network.tr.dualstack;
        environment.etc."networks/srv".source = pkgs.writers.writeJSON "srv" fclib.network.tr.dualstack;
        environment.etc."networks/mgm".source = pkgs.writers.writeJSON "mgm" fclib.network.tr.dualstack;
        environment.etc."networks/fe".source = pkgs.writers.writeJSON "fe" fclib.network.tr.dualstack;

        environment.etc."bind/pri/1.0.0.0.8.3.2.0.2.0.a.2.ip6.arpa.zone".text = ''
          $TTL 86400
          $ORIGIN 1.0.0.0.8.3.2.0.2.0.a.2.ip6.arpa.
          @               86400   IN      SOA ns.dev.gocept.net. hostmaster.fcio.net. (
                                                  2024041000 ; serial
                                                  10800 ; refresh
                                                  900 ; retry
                                                  2419200 ; expire
                                                  1800 ; neg ttl
                                          )
                                          NS      ns.dev.gocept.net.
          $TTL 7200
          1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.3.0.f PTR     whq-router.tr.whq.gocept.net.
          4.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.3.0.f PTR     lou.tr.whq.gocept.net.
          5.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.3.0.f PTR     kenny01.tr.whq.gocept.net.
        '';

        environment.etc."bind/pri/252.105.185.in-addr.arpa.zone".text = ''
          $TTL 86400
          $ORIGIN 252.105.185.in-addr.arpa.
          @               86400   IN      SOA ns.dev.gocept.net. hostmaster.fcio.net. (
                                                  2024041000 ; serial
                                                  10800 ; refresh
                                                  900 ; retry
                                                  2419200 ; expire
                                                  1800 ; neg ttl
                                          )
                                          NS      ns.dev.gocept.net.
          $TTL 7200
          1                               PTR     rzob-router.fe.rzob.gocept.net.
        '';

        environment.etc."bind/pri/127.zone".text = ''
          $TTL 1W
          @ IN  SOA 127.in-addr.arpa. root.localhost. (
                                                  1
                                                  28800
                                                  14400
                                                  604800
                                                  86400 )
              NS  localhost.

          1.0.0   PTR localhost.
        '';

        environment.etc."bind/pri/localhost.zone".text = ''
          $TTL 1W
          @       IN      SOA     localhost. root.localhost.  (
                                                2008122601 ; Serial
                                                28800      ; Refresh
                                                14400      ; Retry
                                                604800     ; Expire - 1 week
                                                86400 )    ; Minimum
          @   IN      NS      localhost.
          @   IN  A 127.0.0.1

          @   IN  AAAA  ::1
        '';

        environment.etc."bind/external-zones.conf".text = ''
          zone "gocept.net" IN {
              type master;
              file "/etc/bind/pri/gocept.net-external.zone";
          };

          zone "1.0.0.0.8.3.2.0.2.0.a.2.ip6.arpa" IN {
              type master;
              file "/etc/bind/pri/1.0.0.0.8.3.2.0.2.0.a.2.ip6.arpa.zone";
          };

          zone "252.105.185.in-addr.arpa" IN {
              type master;
              file "/etc/bind/pri/252.105.185.in-addr.arpa.zone";
          };
        '';

        environment.etc."bind/internal-zones.conf".text = ''
          zone "gocept.net" IN {
              type master;
              file "/etc/bind/pri/gocept.net-internal.zone";
          };

          zone "1.0.0.0.8.3.2.0.2.0.a.2.ip6.arpa" IN {
              type master;
              file "/etc/bind/pri/1.0.0.0.8.3.2.0.2.0.a.2.ip6.arpa.zone";
          };

          zone "252.105.185.in-addr.arpa" IN {
              type master;
              file "/etc/bind/pri/252.105.185.in-addr.arpa.zone";
          };
        '';

        environment.etc."bind/pri/gocept.net-external.zone".text = ''
          $TTL 86400
          $ORIGIN gocept.net.
          @               86400   IN      SOA ns.dev.gocept.net. hostmaster.fcio.net. (
                                                  2024041000 ; serial
                                                  10800 ; refresh
                                                  900 ; retry
                                                  2419200 ; expire
                                                  1800 ; neg ttl
                                          )
                                          NS      ns.dev.gocept.net.
          $TTL 7200
          test00                        AAAA    2a02:248:101:63::222
          test00.fe.rzob                A       195.62.125.222
        '';

        environment.etc."bind/pri/gocept.net-internal.zone".text = ''
          $TTL 86400
          $ORIGIN gocept.net.
          @               86400   IN      SOA ns.dev.gocept.net. hostmaster.fcio.net. (
                                                  2024041001 ; serial
                                                  10800 ; refresh
                                                  900 ; retry
                                                  2419200 ; expire
                                                  1800 ; neg ttl
                                          )
                                          NS      ns.dev.gocept.net.
          $TTL 7200
          test00                        AAAA    2a02:248:101:63::222
          test00                        A       172.22.22.222
        '';

        flyingcircus.services.dhcpd4.localconfig = {
          shared-networks = [
            {
              name = "fe";
              subnet4 = [
                {
                  subnet = "172.20.2.0/25";
                  id = 1;
                  option-data = [
                    {
                      name = "routers";
                      data = "172.20.2.1";
                    }
                  ];
                  pools = [
                    {
                      pool = "172.20.2.17 - 172.20.2.51";
                    }
                    {
                      pool = "172.20.2.125 - 172.20.2.125";
                    }
                  ];
                }
              ];
            }
          ];
        };

        flyingcircus.services.dhcpd6.localconfig = {
          shared-networks = [
            {
              name = "fe";
              subnet6 = [
                {
                  subnet = "fdfc:c12:c05:2::/64";
                  id = 1;
                }
              ];
            }
          ];
        };

        # fc-trafficclient tries to connect to the directory. So far we do not test
        # any actual functionality of that service here, so just mock it away to avoid
        # - having to expose an /etc/nixos/enc.json
        # - having to provide a fake directory to connect and report to
        systemd.services.fc-trafficclient.serviceConfig.ExecStart =
          lib.mkForce "${pkgs.coreutils}/bin/true";

        flyingcircus.enc.name = "router${toString id}";
        flyingcircus.enc.parameters = {
          location = "test";
          resource_group = "router";
          interfaces.mgm = {
            mac = "52:54:00:12:01:0${toString id}";
            bridged = false;
            networks = {
              "172.20.1.0/24" = [ "172.20.1.1${toString id}" ];
              "fdfc:c12:c05:1::/64" = [ "fdfc:c12:c05:1::1${toString id}" ];
            };
            gateways = {
              "172.20.1.0/24" = "172.20.1.1";
              "fdfc:c12:c05:1::/64" = "fdfc:c12:c05:1::1";
            };
            nics = [
              {
                "mac" = "52:54:00:12:01:0${toString id}";
                "external_label" = "label-management";
              }
            ];
          };
          interfaces.fe = {
            mac = "52:54:00:12:02:0${toString id}";
            bridged = false;
            networks = {
              "172.20.2.0/24" = [ "172.20.2.1${toString id}" ];
              "fdfc:c12:c05:2::/64" = [ "fdfc:c12:c05:2::1${toString id}" ];
            };
            gateways = {
              "172.20.2.0/24" = "172.20.2.1";
              "fdfc:c12:c05:2::/64" = "fdfc:c12:c05:2::1";
            };
            nics = [
              {
                "mac" = "52:54:00:12:02:0${toString id}";
                "external_label" = "label-fe";
              }
            ];
          };
          interfaces.srv = {
            mac = "52:54:00:12:03:0${toString id}";
            bridged = false;
            networks = {
              "172.20.3.0/24" = [ "172.20.3.1${toString id}" ];
              "172.30.3.0/24" = [ "172.30.3.1${toString id}" ];
              "fdfc:c12:c05:3::/64" = [ "fdfc:c12:c05:3::1${toString id}" ];
            };
            gateways = {
              "172.20.3.0/24" = "172.20.3.1";
              "fdfc:c12:c05:3::/64" = "fdfc:c12:c05:3::1";
            };
            nics = [
              {
                "mac" = "52:54:00:12:03:0${toString id}";
                "external_label" = "label-srv";
              }
            ];
          };
          interfaces.tr = {
            mac = "52:54:00:12:06:0${toString id}";
            bridged = false;
            networks = {
              "172.20.6.0/24" = [ "172.20.6.1${toString id}" ];
              "fdfc:c12:c05:6::/124" = [ "fdfc:c12:c05:6::1${toString id}" ];
            };
            gateways = {
              "172.20.6.0/24" = "172.20.6.1";
              "fdfc:c12:c05:6::/124" = "fdfc:c12:c05:6::1";
            };
            nics = [
              {
                "mac" = "52:54:00:12:03:0${toString id}";
                "external_label" = "label-tr";
              }
            ];
          };
        };
        flyingcircus.encServices = [
          {
            address = "sensu.gocept.net";
            location = "test";
            password = "uiae";
            service = "sensuserver-source-address";
            ips = [
              "172.20.2.200"
            ];
          }
        ];

        services.telegraf.enable = lib.mkForce false;

        specialisation.agentmock =
          let
            agentMock = pkgs.writeShellScript "agent-mock" ''
              msg="fc-keepalived mock called at $(date) with args: $@"
              echo $msg
              echo $msg >> /tmp/agent-mock-called
            '';
          in
          {
            # we cannot plainly merge into `config.specialisations.primary.configuration`
            # anymore, as this is now already an instantiated NixOS config and not
            # just the specified attributes.
            configuration = config.flyingcircus.roles.router.primarySpecialisationConfig // {
              environment.etc."keepalived/fc-keepalived".source = lib.mkForce "${agentMock}";
              system.activationScripts.msg = ''
                echo "This is specialisation agentmock, activated at $(date)"
              '';
            };
          };

        # normally the agent (or on vanilla NixOS systems, `nixos-rebuild`) registers
        # the profile symlink for later access. In tests, the agent is not properly
        # run though. so let's simulate this.

        system.activationScripts.setupSystemProfile = ''
          install -m 0755 -d /nix/var/nix/{gcroots,profiles}/per-user

          system_profile=/nix/var/nix/profiles/system
          if [[ ! -e $system_profile ]]; then
            ln -s $(dirname $0) /nix/var/nix/profiles/system
          fi
        '';
      };

    makeUpstreamRouterConfig =
      { id }:
      {
        config,
        pkgs,
        lib,
        ...
      }:
      let
      in
      {
        virtualisation.vlans = with config.flyingcircus.static.vlanIds; [
          srv
          tr
        ];
        imports = [
          ../../nixos
          ../../nixos/roles
        ];

        flyingcircus.enc.name = "upstream${toString id}";
        flyingcircus.enc.parameters = {
          location = "upstream";
          resource_group = "upstream";
          interfaces.srv = {
            mac = "52:54:00:12:03:0${toString id}";
            bridged = false;
            networks = {
              "10.0.13.0/24" = [ "10.0.13.${toString id}" ];
            };
            gateways = { };
          };
          interfaces.tr = {
            mac = "52:54:00:12:06:0${toString id}";
            bridged = false;
            networks = {
              "10.0.13.0/24" = [ "10.0.13.${toString id}" ];
            };
            gateways = {
            };
          };
        };

      };

    mkTestScript =
      nodes: script:
      ''
        import importlib.util
        import sys
        from importlib.machinery import ModuleSpec

        import rich

        # workaround to import a local module that is not a package
        spec = importlib.util.spec_from_file_location("helpers", "${./helpers.py}")
        helpers = importlib.util.module_from_spec(spec)
        sys.modules["helpers"] = helpers
        spec.loader.exec_module(helpers)

        #Machine.r = property(helpers.r)

        # initialise node initial system paths
      ''
      + "\n"
      + builtins.concatStringsSep "\n" (
        lib.mapAttrsToList (
          nodeName: node:
          ''${nodeName}.r = helpers.Router(${nodeName}, "${toString node.system.build.toplevel}")''
        ) nodes
      )
      + "\n"
      + script;
  in
  {
    name = "router";

    testCases.primary = {

      nodes = {
        primary = makeRouterConfig { id = 1; };
      };

      extraPythonPackages = ps: [ ps.rich ];
      skipTypeCheck = true; # due to cursed importing of helpers

      testScript =
        { nodes, ... }:
        let
          feInterface = nodes.primary.fclib.network.fe.interface;
          srvInterface = nodes.primary.fclib.network.srv.interface;
        in
        mkTestScript nodes ''
          pp = rich.print
          primary.wait_for_unit("default.target")

          with subtest("networking"):
            pp(primary.succeed("ip a"))
            pp(primary.succeed("ip r"))
            pp(primary.succeed("iptables -L -n"))
            pp(primary.succeed("ip6tables -L -n"))
            pp(primary.succeed("systemctl status -l firewall"))


          with subtest("wait for keepalived to become active"):
            primary.wait_until_succeeds("systemctl is-active keepalived")

          with subtest("wait for the system to switch to primary"):
            primary.r.wait_until_is_primary()

          with subtest("bird2 is configured as primary"):
            primary.wait_for_unit("bird")
            primary.succeed("grep PRIMARY=1 /etc/bird/bird.conf")
            pp(primary.succeed("cat /etc/bird/bird.conf"))

          with subtest("radvd is running"):
            pp(primary.succeed("systemctl cat -l radvd"))
            pp(primary.execute("systemctl is-active radvd"))
            primary.wait_for_unit("radvd")

          with subtest("bind is running"):
            primary.wait_for_unit("bind")

          with subtest("kea-dhcp4-server is running"):
            import time
            time.sleep(10)
            print(primary.execute("journalctl -u kea-dhcp4-server")[1])
            primary.wait_for_unit("kea-dhcp4-server")

          with subtest("kea-dhcp6-server is running"):
            primary.wait_for_unit("kea-dhcp6-server")

          with subtest("tftp daemon (atftpd) is running and serves files"):
            primary.wait_for_unit("atftpd")
            primary.succeed("${pkgs.inetutils}/bin/tftp -v 127.0.0.1 <<< 'get flyingcircus.ipxe'")
            primary.succeed("stat flyingcircus.ipxe")
            primary.succeed("${pkgs.inetutils}/bin/tftp -v 127.0.0.1 <<< 'get undionly.kpxe'")
            primary.succeed("stat undionly.kpxe")

          with subtest("pmacctd should be running for fe and srv interfaces"):
            primary.wait_for_unit("pmacctd-${feInterface}")
            primary.wait_for_unit("pmacctd-${srvInterface}")

          with subtest("pmacctd does not issue warnings and binds to correct interfaces"):
            print(primary.execute("journalctl -b -u pmacctd*")[1])
            # deliberately broad condition: We'd like to know about each warning for now.
            # the one we actually want to ensure to not exist for PL-133497 is:
            # WARN: [/nix/store/9pa54fv0jksk9kx4zlq98y3mh3676hk1-pmacctd-brsrv.conf:1] Unknown key: interface. Ignored.
            primary.fail('journalctl -b -u pmacctd* --grep "WARN:"')

            primary.succeed('journalctl -b -u pmacctd-${feInterface} | tee | grep "\[${feInterface},0\] link type is: 1"')
            primary.succeed('journalctl -b -u pmacctd-${srvInterface} --grep "\[${srvInterface},0\] link type is: 1"')

          with subtest("trafficclient timer should be active"):
            primary.wait_for_unit("fc-trafficclient.timer")
        '';
    };

    testCases.interactive = {
      nodes = {
        router = makeRouterConfig { id = 1; };
      };

      extraPythonPackages = ps: [ ps.rich ];
      skipTypeCheck = true; # due to cursed importing of helpers
      testScript =
        { nodes, ... }:
        mkTestScript nodes ''
          print(f"Initial system path: {router.r.system_top_level}")
          router.r.secondary_system
          print("primary ?", router.r.is_primary)
          router.r.wait_until_is_secondary()
        '';
    };

    testCases.secondary = {
      nodes = {
        secondary = makeRouterConfig { id = 1; };
      };

      extraPythonPackages = ps: [ ps.rich ];
      skipTypeCheck = true; # due to cursed importing of helpers
      testScript =
        { nodes, ... }:
        let
          feInterface = nodes.secondary.fclib.network.fe.interface;
          srvInterface = nodes.secondary.fclib.network.srv.interface;
        in
        mkTestScript nodes ''
          pp = rich.print
          secondary.wait_for_unit("default.target")

          with subtest("networking"):
            pp(secondary.succeed("ip a"))
            pp(secondary.succeed("ip r"))
            pp(secondary.succeed("iptables -L -n"))
            pp(secondary.succeed("ip6tables -L -n"))
            pp(secondary.succeed("systemctl status -l firewall"))

          with subtest("pmacctd should be running for fe and srv interfaces"):
            print(secondary.execute("systemctl status pmacctd*")[1])
            print(secondary.execute("journalctl -b -u pmacctd*")[1])

            secondary.wait_for_unit("pmacctd-${feInterface}")
            secondary.wait_for_unit("pmacctd-${srvInterface}")

          with subtest("trafficclient timer should be active"):
            secondary.wait_for_unit("fc-trafficclient.timer")

          with subtest("wait for keepalived to become active"):
            print(secondary.succeed("cat /etc/keepalived/keepalived.conf"))
            print(secondary.succeed("systemctl cat keepalived"))
            secondary.wait_until_succeeds("systemctl is-active keepalived")
            secondary.r.wait_until_is_primary()

          with subtest("keepalived: write stopper file"):
            secondary.execute("sed -i 'c 1' /etc/keepalived/stop")
            secondary.r.wait_until_is_secondary()

          with subtest("radvd should not run"):
            secondary.fail("systemctl is-active radvd")

          with subtest("bird is configured as secondary"):
            secondary.wait_for_unit("bird")
            secondary.succeed("grep PRIMARY=0 /etc/bird/bird.conf")
            print(secondary.succeed("cat /etc/bird/bird.conf"))

          with subtest("stopping keepalived"):
            secondary.systemctl("stop keepalived")
            secondary.systemctl("stop keepalived-boot-delay.timer")
            secondary.r.wait_until_is_secondary()

          with subtest("bind is running"):
            secondary.wait_for_unit("bind")
        '';
    };

    testCases.agentswitch = {
      nodes = {
        router = makeRouterConfig { id = 1; };
      };

      extraPythonPackages = ps: [ ps.rich ];
      skipTypeCheck = true; # due to cursed importing of helpers
      testScript =
        { nodes, ... }:
        mkTestScript nodes ''
          with subtest("Should become primary router"):
            router.wait_until_succeeds("systemctl is-active keepalived")
            router.r.wait_until_is_primary()
            print(router.succeed("systemctl cat keepalived"))

          with subtest("Switch to system with mocked fc-keepalived command"):
            agent_before = router.execute("readlink -f /etc/keepalived/fc-keepalived")[1]
            print(router.succeed("systemctl status -l keepalived"))
            print(router.succeed("systemctl cat keepalived"))
            print(router.succeed("fc-manage activate-configuration --specialisation agentmock"))
            # fc-keepalived script symlink changes its target after activation.
            print(router.succeed("systemctl cat keepalived"))
            print(router.execute("cat /etc/keepalived/fc-keepalived")[1])
            agent_after = router.execute("readlink -f /etc/keepalived/fc-keepalived")[1]

            for x in range(30):
              print(f"Waiting for fc-keepalived script to change, try {x}")
              if agent_before != agent_after:
                break
              router.sleep(1)
            else:
              assert agent_before != agent_after, "fc-keepalived script didn't change!"

          with subtest("keepalived should call the fc-keepalived mock when the stop file is changed"):
            router.execute("sed -i 'c 1' /etc/keepalived/stop")
            router.wait_until_succeeds("cat /tmp/agent-mock-called")

          with subtest("Firewall configuration should not differ between primary and secondary"):
            primary_system = router.r.primary_system
            secondary_system = router.r.secondary_system

            primary_firewall = router.execute(f"cat {primary_system}/etc/systemd/system/firewall.service")
            secondary_firewall = router.execute(f"cat {secondary_system}/etc/systemd/system/firewall.service")
            assert primary_firewall[1] == secondary_firewall[1], "firewall configuration differs between primary and secondary system"

          print(router.succeed("journalctl -xb -u keepalived"))
        '';
    };

    testCases.failover = {
      nodes = {
        router1 = makeRouterConfig { id = 1; };
        router2 = makeRouterConfig { id = 2; };
      };

      extraPythonPackages = ps: [ ps.rich ];
      skipTypeCheck = true; # due to cursed importing of helpers
      testScript =
        { nodes, ... }:
        mkTestScript nodes ''
          with subtest("First router should become primary"):
            router1.wait_until_succeeds("systemctl is-active keepalived")
            router2.wait_until_succeeds("systemctl is-active keepalived")
            router1.r.wait_until_is_primary()
            router2.r.wait_until_is_secondary()

          with subtest("router1: pull mgm, should NOT switch to router2"):
            router1.send_monitor_command("set_link virtio-net-pci.1 off")
            router1.sleep(3)
            router2.r.wait_until_is_secondary()
            router1.r.wait_until_is_primary()
            router1.send_monitor_command("set_link virtio-net-pci.1 on")

          with subtest("router1: write stopper file, should switch to router2"):
            router1.succeed("sed -i 'c 1' /etc/keepalived/stop")
            router2.r.wait_until_is_primary()
            router1.r.wait_until_is_secondary()
            router1.succeed("sed -i 'c 0' /etc/keepalived/stop")

          with subtest("router2: pull fe, should switch to router1"):
            router2.send_monitor_command("set_link virtio-net-pci.2 off")
            router1.r.wait_until_is_primary()
            router2.r.wait_until_is_secondary()
            router2.send_monitor_command("set_link virtio-net-pci.2 on")

          with subtest("router1: pull srv, should switch to router2"):
            router1.send_monitor_command("set_link virtio-net-pci.3 off")
            router1.r.wait_until_is_secondary()
            router2.r.wait_until_is_primary()
            router1.send_monitor_command("set_link virtio-net-pci.3 on")

          print(router1.succeed("journalctl -xb -u keepalived"))
          print(router2.succeed("journalctl -xb -u keepalived"))
        '';
    };

    testCases.maintenance = {
      nodes = {
        router1 = makeRouterConfig { id = 1; };
        router2 = makeRouterConfig { id = 2; };
      };

      extraPythonPackages = ps: [ ps.rich ];
      skipTypeCheck = true; # due to cursed importing of helpers
      testScript =
        { nodes, ... }:
        let
          fc-keepalived = "JOURNAL_STREAM= fc-keepalived";
        in
        mkTestScript nodes ''
          with subtest("First router should become primary"):
            router1.wait_until_succeeds("systemctl is-active keepalived")
            router2.wait_until_succeeds("systemctl is-active keepalived")
            router1.r.wait_until_is_primary()
            router2.r.wait_until_is_secondary()

          with subtest("router1: fc-keepalived enter-maintenance, should switch to router2"):
            router1.succeed("${fc-keepalived} enter-maintenance")
            router1.r.wait_until_is_secondary()
            router2.r.wait_until_is_primary()
            router1.succeed("${fc-keepalived} leave-maintenance")

          import time

          with subtest("router2: run a maintenance activity, should switch to router1"):
            router2.execute('fc-maintenance -v request script test "sleep 3"')
            maintenance_out = router2.succeed("JOURNAL_STREAM= fc-maintenance -v run --no-online --run-all-now 2>&1")
            print("fc-maintenance output:")
            print("="*80)
            print(maintenance_out)
            print(router1.execute("journalctl --since -20s")[1])
            print(router2.execute("journalctl --since -20s")[1])
            router2.r.wait_until_is_secondary()
            router1.r.wait_until_is_primary()
            assert router1.r.is_primary, "router 1 is not primary"
            assert not router2.r.is_primary, "router 2 is still primary"

          with subtest("router1: fc-keepalived check should be green"):
            print(router1.succeed("${fc-keepalived} check"))

          with subtest("router2: fc-keepalived check should be green"):
            print(router2.succeed("${fc-keepalived} check"))

          print(router1.execute("cat /var/log/fc-agent.log")[1])

          with subtest("keepalived router state files should reflect reality"):
            router1_state = router1.succeed("cat /run/keepalived/state").strip()
            assert router1_state == "master", f"router1 state file should have 'master', got {router1_state}"
            router2_state = router2.succeed("cat /run/keepalived/state").strip()
            assert router2_state == "backup", f"router2 state file should have 'backup', got {router2_state}"
        '';
    };

    testCases.whq_dev = {

      nodes = {
        router1 = makeRouterConfig { id = 1; };
        router2 = makeRouterConfig { id = 2; };
        upstream1 = makeUpstreamRouterConfig { id = 3; };
        upstream2 = makeUpstreamRouterConfig { id = 4; };
        vm =
          { pkgs, ... }:
          {
            imports = [
              (fcConfig { id = 5; })
            ];
          };
      };

      extraPythonPackages = ps: [ ps.rich ];
      skipTypeCheck = true; # due to cursed importing of helpers
      testScript =
        { nodes, ... }:
        mkTestScript nodes ''
          router1.wait_for_unit("default.target")

          with subtest("networking"):
            print(router1.succeed("iptables -L -n"))
            print(router1.succeed("ip6tables -L -n"))
            print(router1.succeed("ip a"))
            print(router1.succeed("ip r"))
        '';
    };
  }
)
