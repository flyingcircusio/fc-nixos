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
      inherit (config) fclib;
    in
    {
      virtualisation.vlans = with config.flyingcircus.static.vlanIds; [ mgm fe srv tr ];
      imports = [ <fc/nixos> <fc/nixos/roles> ];

      flyingcircus.roles.router.enable = true;

      # Copied from flyingcircus-physical.nix
      networking.firewall.trustedInterfaces = [ "ethsto" "ethstb" "ethmgm" ];

      environment.etc."networks/tr".source = fclib.writePrettyJSON "tr" fclib.network.tr.dualstack;

      flyingcircus.enc.name = "router${toString id}";
      flyingcircus.enc.parameters = {
        location = "test";
        resource_group = "router";
        interfaces.mgm = {
          mac = "52:54:00:12:01:0${toString id}";
          bridged = false;
          networks = {
            "172.20.1.0/24" = [ "172.20.1.${toString id}" ];
            "2a02:238:f030:1c1::/64" = [ "2a02:238:f030:1c1::${toString id}" ];
          };
          gateways = {};
        };
        interfaces.fe = {
          mac = "52:54:00:12:02:0${toString id}";
          bridged = false;
          networks = {
            "172.20.2.0/24" = [ "172.20.2.${toString id}" ];
            "2a02:238:f030:1c2::/64" = [ "2a02:238:f030:1c2::${toString id}" ];
          };
          gateways = {};
        };
        interfaces.srv = {
          mac = "52:54:00:12:03:0${toString id}";
          bridged = false;
          networks = {
            "172.20.3.0/24" = [ "172.20.3.${toString id}" ];
            "172.30.3.0/24" = [ "172.30.3.${toString id}" ];
            "2a02:238:f030:1c3::/64" = [ "2a02:238:f030:1c3::${toString id}" ];
          };
          gateways = {};
        };
        interfaces.tr = {
          mac = "52:54:00:12:06:0${toString id}";
          bridged = false;
          networks = {
            "172.20.6.0/24" = [ "172.20.6.${toString id}" ];
            "2a02:238:f030:1c6::/124" = [ "2a02:238:f030:1c6::${toString id}" ];
          };
          gateways = {
            "172.20.6.0/24" = "172.20.6.254";
            "2a02:238:f030:1c6::/124" = "2a02:238:f030:1c6::3";
          };
        };
      };

      services.telegraf.enable = lib.mkForce false;

      specialisation.agentmock = let
        agentMock = pkgs.writeShellScript "agent-mock" ''
          msg="Agent Mock called at $(date) with args: $@"
          echo $msg
          echo $msg >> /tmp/agent-mock-called
        '';
      in {
        configuration = config.specialisation.primary.configuration // {
          environment.etc."keepalived/fc-manage".source = lib.mkForce "${agentMock}";
          system.activationScripts.msg = ''
            echo "This is specialisation agentmock, activated at $(date)"
          '';
        };
      };

     system.activationScripts.setupSystemProfile = ''
       system_profile=/nix/var/nix/profiles/system
       if [[ ! -e $system_profile ]]; then
         ln -s $(dirname $0) /nix/var/nix/profiles/system
       fi
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
          gateways = {
          };
        };
      };

    };

  mkTestScript = script: ''
    import sys
    sys.path.extend([
      "${pkgs.python38Packages.rich}/lib/python3.8/site-packages/",
      "${pkgs.writeTextDir "helpers.py" (builtins.readFile ./helpers.py)}"
    ])

    import helpers
    import rich
    Machine.r = property(helpers.r)
  '' + "\n" + script;
in
{
  name = "router";

  testCases.primary = {

    nodes = {
      primary = makeRouterConfig { id = 1; };
    };

    testScript = { nodes, ... }: mkTestScript ''
      pp = rich.print
      primary.wait_for_unit("default.target")

      with subtest("networking"):
        pp(primary.succeed("ip a"))
        pp(primary.succeed("ip r"))
        pp(primary.succeed("iptables -L -n"))
        pp(primary.succeed("ip6tables -L -n"))

      with subtest("wait for keepalived to become active"):
        primary.wait_until_succeeds("systemctl is-active keepalived")

      with subtest("wait for the system to switch to primary"):
        primary.r.wait_until_is_primary()

      with subtest("bird is configured as primary"):
        primary.wait_for_unit("bird")
        primary.succeed("grep PRIMARY=1 /etc/bird/bird.conf")
        pp(primary.succeed("cat /etc/bird/bird.conf"))

      with subtest("bird6 is configured as primary"):
        primary.wait_for_unit("bird6")
        primary.succeed("grep PRIMARY=1 /etc/bird/bird6.conf")
        print(primary.succeed("cat /etc/bird/bird6.conf"))

      with subtest("radvd is running"):
        pp(primary.succeed("systemctl cat -l radvd"))
        pp(primary.execute("systemctl is-active radvd"))
        primary.wait_for_unit("radvd")

      with subtest("bind is running"):
        primary.wait_for_unit("bind")
    '';
  };

  testCases.interactive = {
    nodes = {
      router = makeRouterConfig { id = 1; };
    };

    testScript = { nodes, ... }: mkTestScript ''
      print(f"Initial system path: {router.r.initial_system_path}")
      router.r.secondary_system
      print("primary ?", router.r.is_primary())
      router.r.wait_until_is_secondary()
    '';
  };

  testCases.secondary = {
    nodes = {
      secondary = makeRouterConfig { id = 1; };
    };

    testScript = { nodes, ... }: mkTestScript ''
      secondary.wait_for_unit("default.target")

      with subtest("networking"):
        print(secondary.succeed("ip a"))
        print(secondary.succeed("ip r"))
        print(secondary.succeed("iptables -L -n"))
        print(secondary.succeed("ip6tables -L -n"))

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

      with subtest("bird6 is configured as secondary"):
        secondary.wait_for_unit("bird6")
        secondary.succeed("grep PRIMARY=0 /etc/bird/bird6.conf")
        print(secondary.succeed("cat /etc/bird/bird6.conf"))

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

    testScript = { nodes, ... }: mkTestScript ''
      with subtest("Should become primary router"):
        router.wait_until_succeeds("systemctl is-active keepalived")
        router.r.wait_until_is_primary()
        print(router.succeed("systemctl cat keepalived"))

      with subtest("Switch to system with mocked fc-manage command"):
        agent_before = router.execute("readlink -f /etc/keepalived/fc-manage")[1]
        print(router.succeed("systemctl status -l keepalived"))
        print(router.succeed("systemctl cat keepalived"))
        print(router.succeed("/etc/keepalived/fc-manage -v activate-configuration -s agentmock"))
        # Script symlink changes its target, keepalived reloads (it's a primary router)
        print(router.succeed("systemctl cat keepalived"))
        print(router.execute("cat /etc/keepalived/fc-manage")[1])
        agent_after = router.execute("readlink -f /etc/keepalived/fc-manage")[1]

        for x in range(30):
          print(f"Waiting for fc-manage script to change, try {x}")
          if agent_before != agent_after:
            break
          router.sleep(1)
        else:
          assert agent_before != agent_after, "fc-manage script didn't change!"

      with subtest("keepalived should call the fc-manage mock when the stop file is changed"):
        router.execute("sed -i 'c 1' /etc/keepalived/stop")
        router.wait_until_succeeds("cat /tmp/agent-mock-called")

      print(router.succeed("journalctl -xb -u keepalived"))
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

    testScript = {nodes, ...}: mkTestScript ''
      router1.wait_for_unit("default.target")

      with subtest("networking"):
        print(router1.succeed("iptables -L -n"))
        print(router1.succeed("ip6tables -L -n"))
        print(router1.succeed("ip a"))
        print(router1.succeed("ip r"))
    '';
  };
})
