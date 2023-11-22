import ../make-test-python.nix ({ pkgs, ... }:
let
  router =
    { config, pkgs, ... }:
    with pkgs.lib;
    let
      vlanIfs = range 1 (length config.virtualisation.vlans);
    in {
      environment.systemPackages = with pkgs; [ iptables curl ];
      virtualisation.vlans = [ 1 2 3 ];  # fe srv tr
      boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = true;
      networking = {
        useDHCP = false;
        firewall.allowPing = true;
        firewall.checkReversePath = true;
        interfaces = mkForce (listToAttrs (flip map vlanIfs (n:
          nameValuePair "eth${toString n}" {
            ipv4.addresses = [
              { address = "10.51.${toString n}.1"; prefixLength = 24; }
            ];
            ipv6.addresses = [
              { address = "2001:db8:${toString n}::1"; prefixLength = 64; }
            ];
          })));
      };

    };

  encInterfaces = id: {
    fe = {  # VLAN 1
      mac = "52:54:00:12:01:0${id}";
      bridged = false;
      networks = {
        "10.51.1.0/24" = [ "10.51.1.1${id}" "10.51.1.2${id}" ];
        "2001:db8:1::/64" = [ "2001:db8:1::1${id}" "2001:db8:1::2${id}" ];
      };
      gateways = {
        "10.51.1.0/24" = "10.51.1.1";
        "2001:db8:1::/64" = "2001:db8:1::1";
      };
    };
    srv = {  # VLAN 2
      mac = "52:54:00:12:02:0${id}";
      bridged = false;
      networks = {
        "10.51.2.0/24" = [ "10.51.2.1${id}" "10.51.2.2${id}" ];
        "2001:db8:2::/64" = [ "2001:db8:2::1${id}" "2001:db8:2::2${id}" ];
      };
      gateways = {
        "10.51.2.0/24" = "10.51.2.1";
        "2001:db8:2::/64" = "2001:db8:2::1";
      };
    };
  };

in {
  name = "network";
  testCases = {

    loopback = {
      name = "loopback";
      machine = {
          imports = [ ../../nixos ../../nixos/roles ];
      };
      testScript = ''
        machine.wait_for_unit("network.target")
        machine.succeed("ip addr show lo | grep -q 'inet 127.0.0.1/8 '")
        machine.succeed("ip addr show lo | grep -q 'inet6 ::1/128 '")
      '';
    };

    wireguard = {
      name = "wireguard";
      machine = {
        imports = [ ../../nixos ../../nixos/roles ];
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
      machine =
        { pkgs, ... }:
        {
          imports = [ ../../nixos ../../nixos/roles ];
          virtualisation.interfaces = {
            ethfe = { vlan = 1; };
            ethsrv = { vlan = 2; };
          };
          flyingcircus.enc.parameters.interfaces = encInterfaces "1";
          flyingcircus.encAddresses = [
            {
              name = "machine";
              ip = "10.51.2.11";
            }
            {
              name = "other";
              ip = "10.51.2.12";
            }
          ];

          networking.domain = "fcio.net";
        };

      testScript = let
        gethostbyname = pkgs.writeScript "gethostbyname.py" ''
          #!${pkgs.python3}/bin/python
          import socket
          import sys
          print(socket.gethostbyname(sys.argv[1]), end="")
        '';
      in ''
        machine.wait_for_unit("network.target")
        with subtest("'machine' should resolve to own srv address"):
          ip = machine.succeed("${gethostbyname} machine")
          assert ip == "10.51.2.11", f"resolved to {ip}"

        with subtest("'machine.fcio.net' should resolve to own srv address"):
          ip = machine.succeed("${gethostbyname} machine.fcio.net")
          assert ip == "10.51.2.11", f"resolved to {ip}"

        with subtest("'other' should resolve to foreign srv address"):
          ip = machine.succeed("${gethostbyname} other")
          assert ip == "10.51.2.12", f"resolved to {ip}"

        with subtest("'other.fcio.net' should resolve to foreign srv address"):
          ip = machine.succeed("${gethostbyname} other.fcio.net")
          assert ip == "10.51.2.12", f"resolved to {ip}"
      '';
    };

    ping-vlans = {
      name = "ping-vlans";
      nodes.client =
        { pkgs, ... }:
        {
          imports = [ ../../nixos ../../nixos/roles ];
          virtualisation.interfaces = {
            ethfe = { vlan = 1; };
            ethsrv = { vlan = 2; };
          };
          flyingcircus.enc.parameters.interfaces = encInterfaces "1";
        };
      nodes.router = router;
      testScript = ''
        start_all()
        client.wait_for_unit("network-online.target")
        router.wait_for_unit("network-online.target")

        print("\n* Router network overview\n")
        print(router.succeed("ip a"))
        print("\n* Client network overview\n")
        print(client.succeed("ip a"))
        # ipv6 needs more time, wait until self-ping works
        router.wait_until_succeeds("ping -c1 2001:db8:1::1")
        client.wait_until_succeeds("ping -c1 2001:db8:1::11")

        with subtest("ping fe"):
          client.succeed("ping -I ethfe -c1 10.51.1.1")
          client.succeed("ping -I ethfe -c1 2001:db8:1::1")
          router.succeed("ping -c1 10.51.1.11")
          router.succeed("ping -c1 10.51.1.21")
          router.succeed("ping -c1 2001:db8:1::11")
          router.succeed("ping -c1 2001:db8:1::21")

        with subtest("ping srv"):
          client.succeed("ping -I ethsrv -c1 10.51.2.1")
          client.succeed("ping -I ethsrv -c1 2001:db8:2::1")
          router.succeed("ping -c1 10.51.2.11")
          router.succeed("ping -c1 10.51.2.21")
          router.succeed("ping -c1 2001:db8:2::11")
          router.succeed("ping -c1 2001:db8:2::21")

        with subtest("ping default gateway"):
          client.succeed("ping -c1 10.51.3.1")
          client.succeed("ping -c1 2001:db8:3::1")
      '';
    };

    routes = {
      name = "routes";
      nodes.machine1 =
        { pkgs, ... }:
        {
          imports = [ ../../nixos ../../nixos/roles ];
          virtualisation.interfaces.ethsrv.vlan = 2;
          flyingcircus.enc.parameters.interfaces = {
            srv = {  # VLAN 2
              mac = "52:54:00:12:02:01";
              bridged = false;
              networks = {
                "10.51.2.0/24" = [ "10.51.2.11" ];
                "10.51.3.0/24" = [ ];
                "2001:db8:2::/64" = [ "2001:db8:2::11" ];
                "2001:db8:3::/64" = [ ];
              };
              gateways = {
                "10.51.2.0/24" = "10.51.2.1";
                "2001:db8:2::/64" = "2001:db8:2::1";
              };
            };
          };
        };
      nodes.machine2 =
        { pkgs, ... }:
        {
          imports = [ ../../nixos ../../nixos/roles ];
          virtualisation.interfaces.ethsrv.vlan = 2;
          flyingcircus.enc.parameters.interfaces = {
            srv = {  # VLAN 2
              mac = "52:54:00:12:02:02";
              bridged = false;
              networks = {
                "10.51.2.0/24" = [ ];
                "10.51.3.0/24" = [ "10.51.3.12" ];
                "2001:db8:2::/64" = [ ];
                "2001:db8:3::/64" = [ "2001:db8:3::12" ];
              };
              gateways = {
                "10.51.3.0/24" = "10.51.3.1";
                "2001:db8:3::/64" = "2001:db8:3::1";
              };
            };
          };
        };
      testScript = ''
        start_all()
        machine1.wait_for_unit("network-online.target")
        machine2.wait_for_unit("network-online.target")

        print("\n* Routes machine1\n")
        print(machine1.succeed("ip r"))
        print(machine1.succeed("ip -6 r"))
        print("\n* Routes machine2\n")
        print(machine2.succeed("ip r"))
        print(machine2.succeed("ip -6 r"))

        with subtest("machine1 should be able to ping machine2 via srv v4"):
          machine1.succeed("ping -c1 -w1 10.51.3.12")

        with subtest("machine2 should be able to ping machine1 via srv v4"):
          machine2.succeed("ping -c1 -w1 10.51.2.11")

        # ipv6 needs more time, wait until self-ping works
        machine1.wait_until_succeeds("ping -c1 -w1 2001:db8:2::11")
        machine2.wait_until_succeeds("ping -c1 -w1 2001:db8:3::12")

        with subtest("machine1 should be able to ping machine2 via srv v6"):
          machine1.succeed("ping -c3 -w3 2001:db8:3::12")

        with subtest("machine2 should be able to ping machine1 via srv v6"):
          machine2.succeed("ping -c1 -w1 2001:db8:2::11")
    '';
  };

    firewall =
      let
        firewalledServer =
          { hostId, localConfigPath ? "/etc/local" }:
            { config, pkgs, ... }:
            {
              networking.hostName = "srv${hostId}";
              imports = [ ../../nixos ../../nixos/roles ];
              virtualisation.interfaces = {
                ethfe = { vlan = 1; };
                ethsrv = { vlan = 2; };
              };
              flyingcircus.infrastructureModule = "flyingcircus";
              flyingcircus.enc.parameters.interfaces = encInterfaces hostId;
              flyingcircus.localConfigPath = localConfigPath;
              services.nginx.enable = true;
              services.nginx.virtualHosts."srv${hostId}" = { root = ./.; };
              users.users.s-test = {
                isNormalUser = true;
                extraGroups = [ "service" ];
              };
            };
      in {
        name = "firewall";
        # encInterfaces defines MAC addresses for the first node
        nodes.router = router;
        nodes.srv2 = firewalledServer { hostId = "2"; };
        nodes.srv3 = firewalledServer {
          hostId = "3";
          localConfigPath = ./open-fe-80;
        };
        testScript = ''
          start_all()
          router.wait_for_unit("network-online.target")

          srv2.wait_for_unit("nginx.service")

          with subtest("default firewall"):
            router.fail("curl http://10.51.1.12/default.nix")
            router.fail("curl http://[2001:db8:1::12]/default.nix")
            router.fail("curl http://10.51.2.12/default.nix")
            router.fail("curl http://[2001:db8:2::12]/default.nix")

          srv3.wait_for_unit("nginx.service");
          with subtest("firewall opens FE"):
            router.succeed("curl http://10.51.1.13/default.nix")
            router.succeed("curl http://[2001:db8:1::13]/default.nix")
            router.fail("curl http://10.51.2.13/default.nix")
            router.fail("curl http://[2001:db8:2::13]/default.nix")

          # service user should be able to write to its local config dir
          srv2.succeed('sudo -u s-test touch /etc/local/firewall/test')
        '';
      };
  };
})
