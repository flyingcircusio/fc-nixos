import ./make-test-python.nix ({ lib, pkgs, testlib, ... }:
let
  net6Fe = "2001:db8:1::";
  net6Srv = "2001:db8:2::";

  gw6Fe = net6Fe + "1";
  gw6Srv = net6Srv + "1";
  internal6Srv = net6Srv + "2";
  oclient6Fe = net6Fe + "3";

  net4Fe = "10.0.1";
  net4Srv = "10.0.2";
  net4Vxlan = "10.0.3";

  gw4Fe = net4Fe + ".1";
  gw4Srv = net4Srv + ".1";
  internal4Srv = net4Srv + ".2";
  oclient4Fe = net4Fe + ".3";

  gwFeFqdn = "gw.fe.standalone.testdomain";

in {

  name = "openvpn";
  nodes = {
    gw =
      { config, ... }:
      {
        imports = [ ../nixos ../nixos/roles ];

        environment.etc = {
          # sensu is not enabled in tests, we must copy the check command in order to use it in the test script
          "local/openvpn/check".source = config.flyingcircus.services.sensu-client.checks.openvpn_port.command;
        };

        flyingcircus.roles.external_net.enable = true;

        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.srv = {
            mac = "52:54:00:12:02:01";
            bridged = false;
            networks = {
              "${net4Srv}.0/24" = [ gw4Srv ];
              "${net6Srv}/64" = [ gw6Srv ];
            };
            gateways = {};
          };
          interfaces.fe = {
            mac = "52:54:00:12:01:01";
            bridged = false;
            networks = {
              "${net4Fe}.0/24" = [ gw4Fe ];
              "${net6Fe}/64" = [ gw6Fe ];
            };
            gateways = {};
          };
        };
        networking.domain = "testdomain";
        networking.firewall.allowPing = true;
        # needed for openvpn auth
        users.users.test = {
          initialPassword = "test";
          isNormalUser = true;
        };
        virtualisation.vlans = [ 1 2 ];
      };

    internal =
      { ... }:
      {
        imports = [ ../nixos ../nixos/roles ];

        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.srv = {
            mac = "52:54:00:12:02:02";
            bridged = false;
            networks = {
              "${net4Srv}.0/24" = [ internal4Srv ];
              "${net6Srv}/64" = [ internal6Srv ];
            };
            gateways = {};
          };
        };
        networking.firewall.allowPing = true;
        virtualisation.vlans = [ 2 ];
      };

    oclient =
      { ... }:
      {
        imports = [ ../nixos ../nixos/roles ];
        environment.systemPackages = [ pkgs.openvpn ];

        services.telegraf.enable = false;
        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.fe = {
            bridged = false;
            mac = "52:54:00:12:01:03";
            networks = {
              "${net4Fe}.0/24" = [ oclient4Fe ];
              "${net6Fe}/64" = [ oclient6Fe ];
            };
            gateways = {};
          };
        };
        networking.extraHosts = ''
          ${gw4Fe} ${gwFeFqdn}
          ${gw6Fe} ${gwFeFqdn}
        '';
        virtualisation.vlans = [ 1 ];
      };
  };

  testScript = ''
    start_all()
    # copy client config from gateway to client and set user/pass
    (rc, ovpn) = gw.execute("cat /etc/local/openvpn/*.ovpn")
    oclient.execute(f"echo '{ovpn}' > /tmp/gw.ovpn")
    oclient.execute("echo 'test\ntest' > /tmp/user-pass; chmod 600 /tmp/user-pass")

    gw.wait_for_unit("network-online.target")
    internal.wait_for_unit("network-online.target")
    oclient.wait_for_unit("network-online.target")

    gw.wait_for_unit("openvpn-access.service")
    gw.wait_until_succeeds("ip link show tun0")

    # openvpn gateway should be reachable from the client
    oclient.succeed("ping -c1 ${gwFeFqdn}")
    oclient.succeed("ping -6 -c1 ${gwFeFqdn}")

    # start openvpn client and wait for tunnel device
    oclient.succeed("openvpn --config /tmp/gw.ovpn --auth-user-pass /tmp/user-pass >&2 &")
    oclient.wait_until_succeeds("ip link show tun0")

    # internal machine should be reachable from client via vpn tunnel -> gateway -> internal machine
    oclient.succeed("ping -c1 ${internal4Srv}")
    oclient.succeed("ping -c1 ${internal6Srv}")

    print("======= addresses =========\n")
    print("=== gw:\n")
    print(gw.execute("ip a"))
    print("=== internal:\n")
    print(internal.execute("ip a"))
    print("=== client:\n")
    print(oclient.execute("ip a"))

    print("======= routing =========\n")
    print("=== gw:\n")
    print(gw.execute("ip r"))
    print("=== client:\n")
    print(oclient.execute("ip r"))

    # sensu check for openvpn server should be green
    gw.succeed("/etc/local/openvpn/check")

    gw.succeed("systemctl stop openvpn-access")
    gw.wait_until_fails("ip link show tun0")

    # sensu check should be red when service is stopped
    gw.fail("/etc/local/openvpn/check")
  '';
})
