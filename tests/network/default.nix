import ../make-test-python.nix ({ pkgs, ... }:
let
  router =
    { config, pkgs, ... }:
    with pkgs.lib; {
      imports = [ ../../nixos ../../nixos/roles ];

      environment.systemPackages = with pkgs; [ iptables curl ];
      virtualisation.vlans = [ 2 3 6 ];  # fe srv tr
      boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = true;

      flyingcircus.enc.parameters.interfaces = encInterfaces "1";
    };

  encInterfaces = id: {
    fe = {  # VLAN 2
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
      nics = [
        {"mac" = "52:54:00:12:02:0${id}";
         "external_label" = "fenic${id}"; }
      ];

    };
    srv = {  # VLAN 3
      mac = "52:54:00:12:03:0${id}";
      bridged = false;
      networks = {
        "10.51.3.0/24" = [ "10.51.3.1${id}" "10.51.3.2${id}" ];
        "2001:db8:3::/64" = [ "2001:db8:3::1${id}" "2001:db8:3::2${id}" ];
      };
      gateways = {
        "10.51.3.0/24" = "10.51.3.1";
        "2001:db8:3::/64" = "2001:db8:3::1";
      };
      nics = [
        {"mac" = "52:54:00:12:03:0${id}";
         "external_label" = "srvnic${id}"; }
      ];
    };
  };

in {
  name = "network";
  testCases = {

    loopback = {
      name = "loopback";
      machine = {
          imports = [ ../../nixos ../../nixos/roles ];
          services.telegraf.enable = false;
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
        services.telegraf.enable = false;
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
          virtualisation.vlans = [ 2 3 ];
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
          imports = [ ../../nixos ../../nixos/roles ];
          virtualisation.vlans = [ 2 3 ];
          flyingcircus.enc.parameters.interfaces = encInterfaces "2";
        };
      testScript = ''
        start_all()
        n2_client.wait_for_unit("network-online.target")
        n1_router.wait_for_unit("network-online.target")

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
        { pkgs, ... }:
        {
          imports = [ ../../nixos ../../nixos/roles ];
          virtualisation.vlans = [ 3 ];
          flyingcircus.enc.parameters.interfaces = {
            srv = {  # VLAN 3
              mac = "52:54:00:12:03:01";
              bridged = false;
              networks = {
                "10.51.3.0/24" = [ "10.51.3.11" ];
                "10.51.99.0/24" = [ ];
                "2001:db8:3::/64" = [ "2001:db8:3::11" ];
                "2001:db8:99::/64" = [ ];
              };
              nics = [
                {"mac" = "52:54:00:12:03:01";
                 "external_label" = "srvnic1"; }
              ];
              gateways = {
                "10.51.3.0/24" = "10.51.3.1";
                "2001:db8:3::/64" = "2001:db8:3::1";
              };
            };
          };
        };
      nodes.machine2 =
        { pkgs, ... }:
        {
          imports = [ ../../nixos ../../nixos/roles ];
          virtualisation.vlans = [ 3 ];
          flyingcircus.enc.parameters.interfaces = {
            srv = {  # VLAN 3
              mac = "52:54:00:12:03:02";
              bridged = false;
              networks = {
                "10.51.3.0/24" = [ ];
                "10.51.99.0/24" = [ "10.51.99.12" ];
                "2001:db8:3::/64" = [ ];
                "2001:db8:99::/64" = [ "2001:db8:99::12" ];
              };
              nics = [
                {"mac" = "52:54:00:12:03:02";
                 "external_label" = "srvnic2"; }
              ];
              gateways = {
                "10.51.99.0/24" = "10.51.99.1";
                "2001:db8:99::/64" = "2001:db8:99::1";
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
          machine1.succeed("ping -c1 -w1 10.51.99.12")

        with subtest("machine2 should be able to ping machine1 via srv v4"):
          machine2.succeed("ping -c1 -w1 10.51.3.11")

        # ipv6 needs more time, wait until self-ping works
        machine1.wait_until_succeeds("ping -c1 -w1 2001:db8:3::11")
        machine2.wait_until_succeeds("ping -c1 -w1 2001:db8:99::12")

        with subtest("machine1 should be able to ping machine2 via srv v6"):
          machine1.succeed("ping -c3 -w3 2001:db8:99::12")

        with subtest("machine2 should be able to ping machine1 via srv v6"):
          machine2.succeed("ping -c1 -w1 2001:db8:3::11")
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
              virtualisation.vlans = [ 2 3 ];
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
        nodes.client = router;
        nodes.srv2 = firewalledServer { hostId = "2"; };
        nodes.srv3 = firewalledServer {
          hostId = "3";
          localConfigPath = ./open-fe-80;
        };
        testScript = ''
          start_all()
          client.wait_for_unit("network-online.target")

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
})
