import ./make-test-python.nix ({ lib, pkgs, testlib, ... }:
let
  vxlanId = 2;
  mtu = 1430;

  net6Fe = "2001:db8:1::";
  net6Srv = "2001:db8:2::";
  net6Vxlan = "2001:db8:3::";

  gw6Fe = net6Fe + "1";
  gw6Srv = net6Srv + "1";
  gw6Vxlan = net6Vxlan + "1"; # set by role, don't change it here
  remote6Fe = net6Fe + "2";
  remote6Vxlan = net6Vxlan + "2";
  vclient6Srv = net6Srv + "3";

  net4Srv = "10.0.2";
  net4Vxlan = "10.0.3";

  gw4Srv = net4Srv + ".1";
  gw4Vxlan = net4Vxlan + ".1"; # set by role, don't change it here
  remote4Vxlan = net4Vxlan + ".2";
  vclient4Srv = net4Srv + ".3";

  encServices = [{
    address = "gw";
    service = "external_net-gateway";
    ips = [
      gw4Srv
      gw6Srv
    ];
  }];

in {

  name = "vxlan";
  nodes = {
    gw =
      { config, ... }:
      {
        imports = [ ../nixos ../nixos/roles ];

        flyingcircus.roles.external_net.enable = true;
        flyingcircus.roles.external_net.vxlan4 = net4Vxlan + ".0/24";
        flyingcircus.roles.external_net.vxlan6 = net6Vxlan + "/64";
        # openvpn pki generation takes long, we don't need it for VxLAN
        flyingcircus.roles.openvpn.enable = lib.mkForce false;

        flyingcircus.roles.vxlan.config = {
          local = gw6Fe;
          remote = remote6Fe;
          vid = vxlanId;
          inherit mtu;
        };

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
              "${net6Fe}/64" = [ gw6Fe ];
            };
            gateways = {};
          };
        };
        networking.domain = "testdomain";
        networking.firewall.allowPing = true;
        virtualisation.interfaces = {
          ethsrv = { vlan = 2; };
          ethfe = { vlan = 1; };
        };
      };

    remote =
      { ... }:
      {
        imports = [ ../nixos ../nixos/roles ];

        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.fe = {
            mac = "52:54:00:12:01:02";
            bridged = false;
            networks = {
              "${net6Fe}/64" = [ remote6Fe ];
            };
            gateways = {};
          };
        };
        networking.domain = "testdomain";
        networking.firewall.allowPing = true;
        networking.firewall.logRefusedPackets = true;
        networking.firewall.enable = false;
        services.nginx.enable = true;
        virtualisation.interfaces.ethfe.vlan = 1;
      };

    vclient =
      { ... }:
      {
        imports = [ ../nixos ../nixos/roles ];

        # vxlan-client needs to know where the vxlan gateway is, role activates itself
        flyingcircus.enc_services = encServices;

        flyingcircus.roles.external_net.vxlan4 = net4Vxlan + ".0/24";
        flyingcircus.roles.external_net.vxlan6 = net6Vxlan + "/64";

        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.srv = {
            mac = "52:54:00:12:02:03";
            bridged = false;
            networks = {
              "${net4Srv}.0/24" = [ vclient4Srv ];
              "${net6Srv}/64" = [ vclient6Srv ];
            };
            gateways = {};
          };
        };
        networking.extraHosts = ''
          ${gw4Srv} gw
          ${gw6Srv} gw
        '';
        networking.firewall.allowPing = true;
        virtualisation.interfaces.ethsrv.vlan = 2;
      };

  };

  testScript = with lib; ''
    start_all()
    gw.wait_for_unit("network-online.target")
    remote.wait_for_unit("network-online.target")
    vclient.wait_for_unit("network-online.target")

    # set up remote side for the VxLAN tunnel
    remote.execute("ip link add nx0 type vxlan id ${toString vxlanId} dev ethfe local ${remote6Fe} remote ${gw6Fe} dstport 8472")
    remote.execute("ip link set up mtu ${toString mtu} dev nx0")
    remote.execute("ip -4 addr add ${remote4Vxlan}/24 dev nx0")
    remote.execute("ip -6 addr add ${remote6Vxlan}/64 dev nx0")
    remote.execute("ip -4 route add ${net4Srv}/24 via ${gw4Vxlan} dev nx0")

    gw.wait_for_unit("vxlan-nx0.service")
    vclient.wait_for_unit("network-external-routing.service")

    vclient.wait_until_succeeds("ping -c1 ${gw6Srv}")
    vclient.succeed("ping -c1 ${gw4Srv}")

    # ping nx0 interface of gateway
    vclient.wait_until_succeeds("ping -c1 ${gw6Vxlan}")
    vclient.succeed("ping -c1 ${gw4Vxlan}")

    # through VxLAN tunnel
    vclient.wait_until_succeeds("ping -c1 ${remote6Vxlan}")
    vclient.succeed("ping -c1 ${remote4Vxlan}")


    print("======= addresses =========\n")
    print("=== gw\n")
    print(gw.execute("ip a"))
    print("=== vclient:\n")
    print(vclient.execute("ip a"))
    print("=== remote:\n")
    print(remote.execute("ip a"))

    print("======= routing =========\n")
    print("=== gw:\n")
    print(gw.execute("ip -4 r"))
    print(gw.execute("ip -6 r"))
    print("=== vclient:\n")
    print(vclient.execute("ip -4 r"))
    print(vclient.execute("ip -6 r"))
    print("=== remote:\n")
    print(remote.execute("ip -4 r"))
    print(vclient.execute("ip -6 r"))

    gw.succeed("systemctl stop vxlan-nx0.service")

    # nx0 device should go away when service is stopped
    gw.wait_until_fails("ip link show nx0")

    # client should not reach remote when VxLAN is down
    vclient.fail("ping -c1 ${remote6Vxlan}")
    vclient.fail("ping -c1 ${remote4Vxlan}")
  '';
})
