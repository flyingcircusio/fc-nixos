import ../make-test-python.nix (
  { pkgs, testlib, ... }:
  # The network / ENC settings in these tests need to stay harmonized with
  # the address allocations that the upstream test harness performs.
  #
  # As of 24.11 the following rules apply:
  #
  # - upstream assumes node IDs based on some (lexicographic?) order
  # - every node automatically receives an IPv6 address (2001:db8:$vlan::$nodeid)
  #   and IPv4 address (192.168.$vlan.$nodeid) from the upstream test harness
  #
  # An example that can become problematic: if we explicitly configure a
  # route/gateway and step on the automatically generated IPs
  let
    router =
      { config, pkgs, ... }:
      with pkgs.lib;
      {
        imports = [
          (testlib.fcConfig {
            id = 1;
            net = {
              fe = true;
              srv = true;
              tr = true;
            };
          })
        ];

        environment.systemPackages = with pkgs; [
          iptables
          curl
        ];
        boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = mkForce true;

        flyingcircus.enc.parameters.interfaces = encInterfaces "1";
      };

    encInterfaces = id: {
      # TODO: this mostly duplicates the network interface definitions of testlib,
      # with a difference in the IPv4 addressess assigned.
      fe = {
        # VLAN 2
        mac = "52:54:00:12:02:0${id}";
        bridged = false;
        networks = {
          "10.51.2.0/24" = [
            "10.51.2.1${id}"
            "10.51.2.2${id}"
          ];
          "2001:db8:2::/64" = [
            "2001:db8:2::1${id}"
            "2001:db8:2::2${id}"
          ];
        };
        gateways = {
          "10.51.2.0/24" = "10.51.2.1";
          "2001:db8:2::/64" = "2001:db8:2::1";
        };
        nics = [
          {
            "mac" = "52:54:00:12:02:0${id}";
            "external_label" = "fenic${id}";
          }
        ];

      };
      srv = {
        # VLAN 3
        mac = "52:54:00:12:03:0${id}";
        bridged = false;
        networks = {
          "10.51.3.0/24" = [
            "10.51.3.1${id}"
            "10.51.3.2${id}"
          ];
          "2001:db8:3::/64" = [
            "2001:db8:3::1${id}"
            "2001:db8:3::2${id}"
          ];
        };
        gateways = {
          "10.51.3.0/24" = "10.51.3.1";
          "2001:db8:3::/64" = "2001:db8:3::1";
        };
        nics = [
          {
            "mac" = "52:54:00:12:03:0${id}";
            "external_label" = "srvnic${id}";
          }
        ];
      };
    };

  in
  {
    name = "network";
    testCases = {

      loopback = {
        name = "loopback";
        nodes.machine = {
          imports = [
            (testlib.fcConfig { id = 1; })
          ];
        };
        testScript = ''
          machine.wait_for_unit("network.target")
          machine.succeed("ip addr show lo | grep -q 'inet 127.0.0.1/8 '")
          machine.succeed("ip addr show lo | grep -q 'inet6 ::1/128 '")
        '';
      };

      sysctl = {
        name = "sysctl";
        nodes.machine =
          { config, lib, ... }:
          {
            imports = [
              (testlib.fcConfig { id = 1; })
            ];

            environment.systemPackages = [ pkgs.procps ];

            networking.interfaces = lib.mapAttrs (_: v: { name = v.name; }) config.virtualisation.interfaces;

            boot.kernel.sysctl = {
              "net.ipv4.conf.ethfe.forwarding" = true;
              "net/ipv6/neigh/ethfe/proxy_delay" = 20;
            };

            specialisation.changed.configuration = {
              boot.kernel.sysctl = {
                "net.ipv4.conf.ethfe.forwarding" = lib.mkForce false;
                "net/ipv6/neigh/ethfe/proxy_delay" = lib.mkForce 40;
                "net.ipv4.conf.ethfe.invalid" = false;
              };
            };
          };

        testScript = ''
          def assertSysctl(sysctl, expected):
            value = machine.succeed(f'sysctl -nb "{sysctl}"')
            t.assertEqual(value, str(expected))

          def testBoot():
            machine.wait_for_unit("network.target")
            assertSysctl("net.ipv4.conf.ethfe.forwarding", 1)
            assertSysctl("net.ipv6.neigh.ethfe.proxy_delay", 20)
            unitStatus = machine.succeed(f"systemctl status network-sysctl-ethfe.service")
            t.assertNotIn("Couldn't write '0' to 'net/ipv4/conf/ethfe/invalid'", unitStatus)

          def testSpecialisation():
            assertSysctl("net.ipv4.conf.ethfe.forwarding", 0)
            assertSysctl("net.ipv6.neigh.ethfe.proxy_delay", 40)
            unitStatus = machine.succeed(f"systemctl status network-sysctl-ethfe.service")
            t.assertIn("Couldn't write '0' to 'net/ipv4/conf/ethfe/invalid'", unitStatus)

          with subtest("after boot"):
            testBoot()

          with subtest("after switch"):
            machine.succeed("/run/current-system/specialisation/changed/bin/switch-to-configuration test")
            testSpecialisation()

          with subtest("after reboot"):
            machine.shutdown()
            machine.start()
            testBoot()
        '';
      };

      wireguard = {
        name = "wireguard";
        nodes.machine = {
          imports = [
            (testlib.fcConfig { id = 1; })
          ];
        };
        testScript = ''
          machine.wait_for_unit("network.target")

          machine.succeed("cat /var/lib/wireguard/privatekey")
          machine.succeed("cat /var/lib/wireguard/publickey")
          machine.succeed("wg")

          print(machine.execute("mount")[1])

          pubkey_acl = machine.execute("getfacl /var/lib/wireguard/publickey")[1]
          assert (pubkey_acl == """\
          # file: var/lib/wireguard/publickey
          # owner: root
          # group: service
          user::rw-
          group::r--
          group:sudo-srv:r--
          mask::r--
          other::---

          """), pubkey_acl

          privkey_acl = machine.execute("getfacl /var/lib/wireguard/privatekey")[1]
          assert (privkey_acl == """\
          # file: var/lib/wireguard/privatekey
          # owner: root
          # group: root
          user::rw-
          group::---
          other::---

          """), privkey_acl
        '';
      };

      name-resolution = {
        nodes.machine =
          { pkgs, ... }:
          {
            imports = [
              (testlib.fcConfig { id = 1; })
            ];
            virtualisation.interfaces = {
              ethfe = {
                vlan = 2;
              };
              ethsrv = {
                vlan = 3;
              };
            };
            flyingcircus.enc.parameters.interfaces = encInterfaces "1";
            flyingcircus.encAddresses = [
              {
                name = "machine";
                ip = "10.51.3.11";
              }
              {
                name = "other";
                ip = "10.51.3.12";
              }
            ];

            networking.domain = "fcio.net";
          };

        testScript =
          let
            gethostbyname = pkgs.writeScript "gethostbyname.py" ''
              #!${pkgs.python3}/bin/python
              import socket
              import sys
              print(socket.gethostbyname(sys.argv[1]), end="")
            '';
          in
          ''
            machine.wait_for_unit("network.target")
            with subtest("'machine' should resolve to own srv address"):
              ip = machine.succeed("${gethostbyname} machine")
              assert ip == "10.51.3.11", f"resolved to {ip}"

            with subtest("'machine.fcio.net' should resolve to own srv address"):
              ip = machine.succeed("${gethostbyname} machine.fcio.net")
              assert ip == "10.51.3.11", f"resolved to {ip}"

            with subtest("'other' should resolve to foreign srv address"):
              ip = machine.succeed("${gethostbyname} other")
              assert ip == "10.51.3.12", f"resolved to {ip}"

            with subtest("'other.fcio.net' should resolve to foreign srv address"):
              ip = machine.succeed("${gethostbyname} other.fcio.net")
              assert ip == "10.51.3.12", f"resolved to {ip}"
          '';
      };

      ping-vlans = {
        name = "ping-vlans";
        # n1/n2 to ensure ordering.
        nodes.n1_router = router; # id 1
        nodes.n2_client =
          { ... }:
          {
            imports = [
              (testlib.fcConfig { id = 2; })
            ];
            virtualisation.interfaces = {
              ethfe = {
                vlan = 2;
              };
              ethsrv = {
                vlan = 3;
              };
            };
            flyingcircus.enc.parameters.interfaces = encInterfaces "2";
          };
        testScript = ''
          start_all()
          n2_client.wait_for_unit("network.target")
          n1_router.wait_for_unit("network.target")

          print("\n* n1_router network overview\n")
          print(n1_router.succeed("ip a"))
          print("\n* n2_client network overview\n")
          print(n2_client.succeed("ip a"))
          # ipv6 needs more time, wait until self-ping works

          n1_router.wait_until_succeeds("ping -c1 2001:db8:2::11")
          n2_client.wait_until_succeeds("ping -c1 2001:db8:2::12")

          with subtest("ping fe"):
            n2_client.succeed("ping -I ethfe -c1 10.51.2.11")
            n2_client.succeed("ping -I ethfe -c1 2001:db8:2::11")
            n1_router.succeed("ping -c1 10.51.2.12")
            n1_router.succeed("ping -c1 10.51.2.22")
            n1_router.succeed("ping -c1 2001:db8:2::12")
            n1_router.succeed("ping -c1 2001:db8:2::22")

          with subtest("ping srv"):
            n2_client.succeed("ping -I ethsrv -c1 10.51.3.11")
            n2_client.succeed("ping -I ethsrv -c1 2001:db8:3::11")
            n1_router.succeed("ping -c1 10.51.3.12")
            n1_router.succeed("ping -c1 10.51.3.22")
            n1_router.succeed("ping -c1 2001:db8:3::12")
            n1_router.succeed("ping -c1 2001:db8:3::22")

          with subtest("ping default gateway"):
            n2_client.succeed("ping -c1 10.51.2.11")
            n2_client.succeed("ping -c1 2001:db8:2::11")
            n2_client.succeed("ping -c1 10.51.3.11")
            n2_client.succeed("ping -c1 2001:db8:3::11")
        '';
      };

      routes = {
        name = "routes";
        nodes.machine1 =
          { pkgs, config, ... }:
          let
            srvEnc = {
              networks = {
                # We pick networks that are completely separate from those configured
                # by the test harness to avoid confusion.
                "10.51.98.0/24" = [ "10.51.98.201" ];
                "10.51.99.0/24" = [ ];
                "2001:db8:98::/64" = [ "2001:db8:98::aa" ];
                "2001:db8:99::/64" = [ ];
              };
              gateways = {
                "10.51.98.0/24" = "10.51.98.1";
                "2001:db8:98::/64" = "2001:db8:98::1";
              };
            };
          in
          {
            imports = [
              (testlib.fcConfig {
                id = 1;
                extraEncParameters.interfaces.srv = srvEnc;
                net = {
                  fe = false;
                  srv = true;
                };
              })
            ];

            environment.etc."test".text = config.systemd.services.network-addresses-ethsrv.script;
          };
        nodes.machine2 =
          { pkgs, config, ... }:
          let
            srvEnc = {
              networks = {
                "10.51.98.0/24" = [ ];
                "10.51.99.0/24" = [ "10.51.99.202" ];
                "2001:db8:98::/64" = [ ];
                "2001:db8:99::/64" = [ "2001:db8:99::bb" ];
              };
              gateways = {
                "10.51.99.0/24" = "10.51.99.1";
                "2001:db8:99::/64" = "2001:db8:99::1";
              };
            };
          in
          {
            imports = [
              (testlib.fcConfig {
                id = 2;
                extraEncParameters.interfaces.srv = srvEnc;
                net = {
                  fe = false;
                  srv = true;
                };
              })
            ];
          };
        testScript = ''
          start_all()
          import difflib
          import sys

          def wait_for_unit(machine, service):
            try:
              machine.wait_for_unit(service)
            except:
              print(machine1.execute(f"journalctl -u {service}")[1])
              raise

          def show_succeed_content(machine, cmd, expected_content):
              code, result = machine.execute(cmd)
              print(f"$ {cmd}")
              print(result)
              assert code == 0, f"ERROR: result code {code}"
              if result != expected_content:
                  print(repr(result))
                  print(repr(expected_content))
                  result = result.splitlines(keepends=True)
                  expected_content = expected_content.splitlines(keepends=True)
                  print(
                    "".join(difflib.ndiff(result, expected_content)), end="")
                  assert False, "Expected content does not match"

          wait_for_unit(machine1, "network-addresses-ethsrv.service")
          wait_for_unit(machine2, "network-addresses-ethsrv.service")

          print("\n* Routes machine1\n")
          # v4 has trailing whitespace, v6 does not
          show_succeed_content(machine1, "ip r", """\
          default via 10.51.98.1 dev ethsrv proto static metric 60\x20
          10.51.98.0/24 dev ethsrv proto kernel scope link src 10.51.98.201\x20
          10.51.99.0/24 dev ethsrv proto static scope link\x20
          192.168.3.0/24 dev ethsrv proto kernel scope link src 192.168.3.1\x20
          """)

          show_succeed_content(machine1, "ip -6 r", """\
          2001:db8:3::/64 dev ethsrv proto kernel metric 256 pref medium
          2001:db8:98::/64 dev ethsrv proto kernel metric 256 pref medium
          2001:db8:99::/64 dev ethsrv proto static metric 1024 pref medium
          fe80::/64 dev ethsrv proto kernel metric 256 pref medium
          default via 2001:db8:98::1 dev ethsrv proto static metric 60 pref medium
          """)
          print("\n* Routes machine2\n")
          show_succeed_content(machine2, "ip r", """\
          default via 10.51.99.1 dev ethsrv proto static metric 60\x20
          10.51.98.0/24 dev ethsrv proto static scope link\x20
          10.51.99.0/24 dev ethsrv proto kernel scope link src 10.51.99.202\x20
          192.168.3.0/24 dev ethsrv proto kernel scope link src 192.168.3.2\x20
          """)
          show_succeed_content(machine2, "ip -6 r", """\
          2001:db8:3::/64 dev ethsrv proto kernel metric 256 pref medium
          2001:db8:98::/64 dev ethsrv proto static metric 1024 pref medium
          2001:db8:99::/64 dev ethsrv proto kernel metric 256 pref medium
          fe80::/64 dev ethsrv proto kernel metric 256 pref medium
          default via 2001:db8:99::1 dev ethsrv proto static metric 60 pref medium
          """)

          with subtest("machine1 should be able to ping machine2 via srv v4"):
            machine1.succeed("ping -c1 -w1 10.51.99.202")

          with subtest("machine2 should be able to ping machine1 via srv v4"):
            machine2.succeed("ping -c1 -w1 10.51.98.201")

          # ipv6 needs more time, wait until self-ping works
          machine1.wait_until_succeeds("ping -c1 -w1 2001:db8:98::aa")
          machine2.wait_until_succeeds("ping -c1 -w1 2001:db8:99::bb")

          with subtest("machine1 should be able to ping machine2 via srv v6"):
            machine1.succeed("ping -c3 -w3 2001:db8:99::bb")

          with subtest("machine2 should be able to ping machine1 via srv v6"):
            machine2.succeed("ping -c1 -w1 2001:db8:98::aa")
        '';
      };

      firewall =
        let
          firewalledServer =
            {
              hostId,
              localConfigPath ? "/etc/local",
            }:
            { config, pkgs, ... }:
            {
              networking.hostName = "srv${toString hostId}";
              imports = [
                (testlib.fcConfig { id = hostId; })
              ];
              virtualisation.interfaces = {
                ethfe = {
                  vlan = 2;
                };
                ethsrv = {
                  vlan = 3;
                };
              };
              flyingcircus.infrastructureModule = "flyingcircus";
              flyingcircus.enc.parameters.interfaces = encInterfaces (toString hostId);
              flyingcircus.localConfigPath = localConfigPath;
              services.nginx.enable = true;
              services.nginx.virtualHosts."srv${toString hostId}" = {
                root = ./.;
              };
              users.users.s-test = {
                isNormalUser = true;
                extraGroups = [ "service" ];
              };
            };
        in
        {
          name = "firewall";
          nodes.client = router;
          nodes.srv2 = firewalledServer { hostId = 2; };
          nodes.srv3 = firewalledServer {
            hostId = 3;
            localConfigPath = ./open-fe-80;
          };
          testScript =
            { nodes, ... }:
            ''
              start_all()
              client.wait_for_unit("network.target")

              print()
              print("client")
              print(client.execute("ip a")[1])
              print(client.execute("ip -4 a")[1])
              print(client.execute("iptables -L -n -v")[1])
              print(client.execute("ip6tables -L -n -v")[1])
              print(client.execute("ip route")[1])

              srv2.wait_for_unit("nginx.service")

              print("srv2")
              print(srv2.execute("ip -4 a")[1])
              print(srv2.execute("iptables -L -n -v")[1])
              print(srv2.execute("ip6tables -L -n -v")[1])
              print(srv2.execute("ip route")[1])

              with subtest("default firewall"):
                client.fail("curl http://10.51.2.12/default.nix")
                client.fail("curl http://[2001:db8:2::12]/default.nix")
                client.fail("curl http://10.51.3.12/default.nix")
                client.fail("curl http://[2001:db8:3::2]/default.nix")

              print(srv2.execute("ip6tables -L -n -v")[1])

              print("srv3")
              print(srv3.execute("ip -4 a")[1])
              print(srv3.execute("iptables -L -n -v")[1])
              print(srv3.execute("ip6tables -L -n -v")[1])
              print(srv3.execute("ip route")[1])

              srv3.wait_for_unit("nginx.service");
              with subtest("firewall opens FE"):
                client.succeed("ping -c 3 10.51.2.13")
                client.succeed("curl http://10.51.2.13/default.nix")
                client.succeed("curl http://[2001:db8:2::13]/default.nix")
                client.fail("curl http://10.51.3.13/default.nix")
                client.fail("curl http://[2001:db8:3::13]/default.nix")

              # service user should be able to write to its local config dir
              srv2.succeed('sudo -u s-test touch /etc/local/firewall/test')
            '';
        };
    };
  }
)
