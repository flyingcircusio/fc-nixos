import ../make-test-python.nix ({ testlib, pkgs, ... }:

with testlib;

let
  networkBase = "192.168.";
  networkBase6 = "fd00:1234:000";
  getNetworkForVLAN = vlan: "${networkBase}${toString vlan}.0/24";
  getNetwork6ForVLAN = vlan: "${networkBase6}${toString vlan}::/48";
  getIPForVLAN = vlan: id: "${networkBase}${toString vlan}.${toString (5 + id)}";
  getIP6ForVLAN = vlan: id: "${networkBase6}${toString vlan}::${toString (5 + id)}";

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

      flyingcircus.enc.name = "router${toString id}";
      flyingcircus.enc.parameters = {
        location = "test";
        resource_group = "router";
        interfaces.mgm = {
          mac = "52:54:00:12:01:0${toString id}";
          bridged = false;
          networks = {
          };
          gateways = {};
        };
        interfaces.fe = {
          mac = "52:54:00:12:02:0${toString id}";
          bridged = false;
          networks = {
          };
          gateways = {};
        };
        interfaces.srv = {
          mac = "52:54:00:12:03:0${toString id}";
          bridged = false;
          networks = {
          };
          gateways = {};
        };
        interfaces.tr = {
          mac = "52:54:00:12:06:0${toString id}";
          bridged = false;
          networks = {
            "172.20.6.0/24" = [ "172.20.6.${toString id}" ];
          };
          gateways = {};
        };
      };
      system.activationScripts.setupSystemProfile = ''
        ln -s $(dirname $0) /nix/var/nix/profiles/system
      '';
    };

  makeUpstreamRouterConfig = { id }:
    { config, pkgs, lib, ... }:
    let
    in
    {
      virtualisation.vlans = with config.flyingcircus.static.vlanIds; [ srv tr ];
      imports = [ <fc/nixos> <fc/nixos/roles> ];

      # Copied from flyingcircus-physical.nix
      networking.firewall.trustedInterfaces = [ "ethtr" ];

      networking.extraHosts = ''
        ${getIPForVLAN 6 1} router1.tr.upstream.fcio.net router1.tr.upstream.gocept.net
        ${getIPForVLAN 6 2} router2.tr.upstream.fcio.net router2.tr.upstream.gocept.net
      '';

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
          gateways = {};
        };
        interfaces.tr = {
          mac = "52:54:00:12:06:0${toString id}";
          bridged = false;
          networks = {
            "10.0.13.0/24" = [ "10.0.13.${toString id}" ];
            #"${networkBase6}d::/48" = [ "${networkBase6}d::${id}" ];
          };
          gateways = {};
        };
      };

    };

  helpers = ''
    from pathlib import Path
    import sys
    import time

    rich_path = "${pkgs.python38Packages.rich}/lib/python3.8/site-packages/"
    sys.path.append(rich_path)

    import rich

    VERBOSE = True

    def pp(*a, **k):
      if VERBOSE:
        rich.print(*a, **k)


    def is_primary(machine):
      system_path = machine.execute("readlink -f /run/current-system")[1].strip()
      return system_path == primary_system


    def wait_until_is_primary(machine):
      while 1:
        current_system = Path(machine.execute("readlink -f /run/current-system")[1].strip())
        print("current specialisation:", machine.execute("cat /etc/specialisation")[1])
        print("current system_path:", current_system)
        if current_system == primary_system:
          machine.wait_for_unit("default.target")
          return
        time.sleep(0.5)


    def wait_until_is_secondary(machine):
      while 1:
        current_system = Path(machine.execute("readlink -f /run/current-system")[1].strip())
        print("current specialisation:", machine.execute("cat /etc/specialisation")[1])
        print("current system_path:", current_system)
        if current_system == secondary_system:
          machine.wait_for_unit("default.target")
          return
        time.sleep(0.5)
  '';
in
{
  name = "router";

  testCases.primary = {

    nodes = {
      primary = makeRouterConfig { id = 1; };
    };

    testScript = {nodes, ...}: helpers + ''
      secondary_system = Path("${nodes.primary.config.system.build.toplevel}")
      primary_system = (secondary_system / "specialisation/primary").resolve()

      print("primary system:", primary_system)
      print("secondary system:", secondary_system)

      primary.wait_for_unit("default.target")

      with subtest("networking"):
        pp(primary.succeed("ip a"))
        pp(primary.succeed("ip r"))
        pp(primary.succeed("iptables -L -n"))
        pp(primary.succeed("ip6tables -L -n"))

      with subtest("wait for keepalived to become active"):
        primary.wait_until_succeeds("systemctl is-active keepalived")

      with subtest("wait for the system to switch to primary"):
        wait_until_is_primary(primary)

      with subtest("bird is configured as primary"):
        primary.wait_for_unit("bird")
        primary.succeed("grep PRIMARY=1 /etc/bird/bird.conf")
        pp(primary.succeed("cat /etc/bird/bird.conf"))

      with subtest("bind is running"):
        primary.wait_for_unit("bind")

      with subtest("radvd is running"):
        pp(primary.succeed("systemctl cat -l radvd"))
        pp(primary.execute("systemctl is-active radvd"))
        primary.wait_for_unit("radvd")
    '';
  };

  testCases.interactive = {
    nodes = {
      router = makeRouterConfig { id = 1; };
    };

    testScript = ''
      import sys
      rich_path = "${pkgs.python38Packages.rich}/lib/python3.8/site-packages/"
      sys.path.append(rich_path)

      import rich

      def pp(machine, cmd):
          import rich
          rich.print(machine.execute(cmd)[1])
    '';
  };

  testCases.secondary = {
    nodes = {
      secondary = makeRouterConfig { id = 1; };
    };

    testScript = {nodes, ...}: helpers + ''
      secondary_system = Path("${nodes.secondary.config.system.build.toplevel}")
      primary_system = (secondary_system / "specialisation/primary").resolve()

      print("primary system:", primary_system)
      print("secondary system:", secondary_system)

      secondary.wait_for_unit("default.target")

      with subtest("networking"):
        print(secondary.succeed("ip a"))
        print(secondary.succeed("ip r"))
        print(secondary.succeed("iptables -L -n"))
        print(secondary.succeed("ip6tables -L -n"))

      with subtest("wait for keepalived to become active"):
        secondary.wait_until_succeeds("systemctl is-active keepalived")
        wait_until_is_primary(secondary)

      with subtest("keepalived: write stopper file"):
        secondary.execute("sed -i 'c 1' /etc/keepalived/stop")
        wait_until_is_secondary(secondary)

      with subtest("radvd should not run"):
        secondary.fail("systemctl is-active radvd")

      with subtest("bird is configured as secondary"):
        secondary.wait_for_unit("bird")
        secondary.succeed("grep PRIMARY=0 /etc/bird/bird.conf")
        print(secondary.succeed("cat /etc/bird/bird.conf"))

      with subtest("stopping keepalived"):
        secondary.systemctl("stop keepalived")
        secondary.systemctl("stop keepalived-boot-delay.timer")
        wait_until_is_secondary(secondary)

      with subtest("bind is running"):
        secondary.wait_for_unit("bind")
    '';
  };

  testCases.whq_dev = {

    nodes = {
      router1 = makeRouterConfig { id = 1; };
      router2 = makeRouterConfig { id = 2; };
      upstream1 = makeUpstreamRouterConfig { id = 3; };
      upstream2 = makeUpstreamRouterConfig { id = 4; };
      vm = { pkgs, ... }: {
        imports = [
          (fcConfig { id = 5; })
        ];
      };


    };
    testScript = {nodes, ...}: helpers + ''
      start_all()
      router1.wait_for_unit("default.target")

      with subtest("networking"):
        print(router1.succeed("iptables -L -n"))
        print(router1.succeed("ip6tables -L -n"))
        print(router1.succeed("ip a"))
        print(router1.succeed("ip r"))
    '';
  };
})
