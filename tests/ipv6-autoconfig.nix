import ./make-test-python.nix (
  { pkgs, testlib, ... }:
  let
    assertZeroSysctl = pkgs.writeScriptBin "assert_zero_sysctl" ''
      set -eu
      sysctl="$1"

      value="$(${pkgs.procps}/bin/sysctl -n -b "$sysctl")"

      [ "$value" == "0" ]
    '';

    makePhysicalHost =
      { id, links }:
      { lib, config, ... }:
      let
        testNodeId = config.virtualisation.test.nodeNumber;
      in
      {
        imports = [
          (testlib.fcConfig {
            inherit id;
            net.mgm = true;
            net.ul = true;
            extraEncParameters = {
              inherit id;
              interfaces.fe.policy = "vxlan";
              interfaces.srv.policy = "vxlan";
              interfaces.ul = {
                policy = "underlay";
                linktype = "bridged";
                nics = map (link: {
                  mac = "52:54:00:12:${lib.toLower (lib.toHexString link)}:0${toString testNodeId}";
                  external_label = "phys/${toString link}";
                }) links;
              };
            };
          })
        ];

        # use the hardware networking config profile
        flyingcircus.networking.physicalHostNetworking = true;
        # extra underlay network links
        virtualisation.vlans = links;

        services.fail2ban.enable = false;

        environment.systemPackages = [ assertZeroSysctl ];
      };
  in
  {
    name = "ipv6-autoconfig";
    testCases = {
      virtual = {
        name = "virtual";
        nodes.machine =
          { ... }:
          {
            imports = [
              (testlib.fcConfig { })
            ];

            environment.systemPackages = [ assertZeroSysctl ];
          };
        testScript = ''
          sysctls = [
              "accept_ra",
              "autoconf",
              "temp_valid_lft",
              "temp_prefered_lft",
              "addr_gen_mode",
          ]

          machine.wait_for_unit("multi-user.target")

          with subtest("testing ipv6 autoconf configuration on ethsrv"):
              for sysctl in sysctls:
                  machine.succeed(f"assert_zero_sysctl net.ipv6.conf.ethsrv.{sysctl}")
          with subtest("testing ipv6 autoconf configuration on ethfe"):
              for sysctl in sysctls:
                  machine.succeed(f"assert_zero_sysctl net.ipv6.conf.ethfe.{sysctl}")
        '';
      };
      hardware = {
        name = "hardware";
        nodes = {
          machine = makePhysicalHost {
            id = 1;
            links = [
              253
              254
            ];
          };
          switch1 = testlib.mockVxlanSwitch {
            id = 2;
            links = [ 253 ];
          };
          switch2 = testlib.mockVxlanSwitch {
            id = 2;
            links = [ 254 ];
          };
        };
        testScript = ''
          sysctls = [
              "accept_ra",
              "autoconf",
              "temp_valid_lft",
              "temp_prefered_lft",
          ]
          hw_sysctls = sysctls.copy()
          hw_sysctls.append("addr_gen_mode")

          start_all()
          for vm in [machine, switch1, switch2]:
              vm.wait_for_unit("multi-user.target")

          virt_links = ["brsrv", "brfe", "vxsrv", "vxfe"];
          phys_links = ["ethmgm", "ul-phys-253", "ul-phys-254"];

          with subtest("testing physical links"):
              for link in phys_links:
                  with subtest(f"testing ipv6 autoconf configuration on {link}"):
                      for sysctl in hw_sysctls:
                          machine.succeed(f"assert_zero_sysctl net.ipv6.conf.{link}.{sysctl}")

          with subtest("testing virtual links"):
              for link in virt_links:
                  with subtest(f"testing ipv6 autoconf configuration on {link}"):
                      for sysctl in sysctls:
                          machine.succeed(f"assert_zero_sysctl net.ipv6.conf.{link}.{sysctl}")
        '';
      };
    };
  }
)
