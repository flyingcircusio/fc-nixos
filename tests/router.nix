import ./make-test-python.nix ({ testlib, ... }:

with testlib;

let
  getIPForVLAN = vlan: id: "192.168.${toString vlan}.${toString (5 + id)}";
  getIP6ForVLAN = vlan: id: "fd00:1234:000${toString vlan}::${toString (5 + id)}";

  makeRouterConfig = { id }:
    { config, pkgs, lib, ... }:
    let
    in
    {
      virtualisation.vlans = with config.flyingcircus.static.vlanIds; [ mgm fe srv tr ];
      imports = [ <fc/nixos> <fc/nixos/roles> ];

      flyingcircus.roles.router.enable = true;

      # Copied from flyingcircus-physical.nix
      networking.firewall.trustedInterfaces = [ "ethsto" "ethstb" "ethmgm" ];

      networking.extraHosts = ''
        ${getIPForVLAN 1 1} router1.mgm.test.fcio.net router1.mgm.test.gocept.net
        ${getIPForVLAN 1 2} router2.mgm.test.fcio.net router2.mgm.test.gocept.net

        ${getIPForVLAN 3 1} directory.fcio.net router1.fcio.net router1

        ${getIP6ForVLAN 3 1} directory.fcio.net router1.fcio.net
      '';

      flyingcircus.enc.name = "host${toString id}";
      flyingcircus.enc.parameters = {
        location = "test";
        resource_group = "test";
        interfaces.mgm = {
          mac = "52:54:00:12:01:0${toString id}";
          bridged = false;
          networks = {
            "192.168.1.0/24" = [ (getIPForVLAN 1 id) ];
            "fd00:1234:0001::/48" =  [ (getIP6ForVLAN 1 id) ];
          };
          gateways = {};
        };
        interfaces.fe = {
          mac = "52:54:00:12:02:0${toString id}";
          bridged = false;
          networks = {
            "192.168.2.0/24" = [ (getIPForVLAN 2 id) ];
            "fd00:1234:0002::/48" =  [ (getIP6ForVLAN 2 id) ];
          };
          gateways = {};
        };
        interfaces.srv = {
          mac = "52:54:00:12:03:0${toString id}";
          bridged = false;
          networks = {
            "192.168.3.0/24" = [ (getIPForVLAN 3 id) ];
            "fd00:1234:0003::/48" =  [ (getIP6ForVLAN 3 id) ];
          };
          gateways = {};
        };
        interfaces.tr = {
          mac = "52:54:00:12:06:0${toString id}";
          bridged = false;
          networks = {
            "192.168.4.0/24" = [ (getIPForVLAN 6 id) ];
            "fd00:1234:0004::/48" =  [ (getIP6ForVLAN 6 id) ];
          };
          gateways = {};
        };
      };
    };
in
{
  name = "router";
  nodes = {
    primary = makeRouterConfig { id = 1; };
    secondary = makeRouterConfig { id = 2; };
  };

  testScript = ''
    with subtest("init"):
      primary.succeed("true")
      secondary.succeed("true")

    with subtest("primary: switching to specialisation primary"):
      primary.succeed("/run/current-system/specialisation/primary/bin/switch-to-configuration test")

    with subtest("secondary: switching to specialisation secondary"):
      secondary.succeed("/run/current-system/specialisation/secondary/bin/switch-to-configuration test")

    primary.wait_for_unit("default.target")
    primary.wait_for_unit("keepalived-boot-delay.timer")
    primary.wait_for_unit("bird")
    primary.wait_for_unit("bind")

    secondary.wait_for_unit("default.target")
    secondary.wait_for_unit("keepalived-boot-delay.timer")
    secondary.wait_for_unit("bird")
    secondary.wait_for_unit("bind")

    with subtest("networking"):
      print(primary.succeed("ip a"))
      print(primary.succeed("ip r"))
      print(primary.succeed("iptables -L -n"))
      print(primary.succeed("ip6tables -L -n"))

    with subtest("primary: radvd is working"):
      primary.wait_for_unit("radvd")
      print(primary.succeed("cat $(systemctl cat radvd | awk '/ExecStart/ { print $7 }')"))

    with subtest("secondary: radvd should not run"):
      secondary.fail("systemctl is-active radvd")

    with subtest("primary: bird is configured as primary"):
      primary.wait_for_unit("bird")
      primary.succeed("grep PRIMARY=1 /etc/bird/bird.conf")
      print(primary.succeed("cat /etc/bird/bird.conf"))

    with subtest("secondary: bird is configured as secondary"):
      secondary.wait_for_unit("bird")
      secondary.succeed("grep PRIMARY=0 /etc/bird/bird.conf")
      print(secondary.succeed("cat /etc/bird/bird.conf"))


    with subtest("primary: wait for keepalived to become active"):
      primary.wait_until_succeeds("systemctl is-active keepalived")

    with subtest("secondary: wait for keepalived to become active"):
      secondary.wait_until_succeeds("systemctl is-active keepalived")
  '';
})
