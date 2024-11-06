# Start VMs with the different kernels we expect to be pre-built
import ./make-test-python.nix ({ pkgs, ... }: let
  stableVersion = pkgs.linuxKernelStable.version;
in {
  name = "kernelversions";
  nodes.rzobProdKernel =
      { pkgs, lib, ... }:
      {
        imports = [ ../nixos ../nixos/roles ];

        flyingcircus.roles.memcached.enable = true;

        flyingcircus.enc.parameters = {
          location = "rzob";
          production = true;
          resource_group = "test";
          interfaces.srv = {
            mac = "52:54:00:12:34:56";
            bridged = false;
            networks = {
              "192.168.101.0/24" = [ "192.168.101.1" ];
              "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::1" ];
            };
            gateways = {};
          };
        };
      };
  nodes.devProdKernel =
        { pkgs, lib, ... }:
        {
          imports = [ ../nixos ../nixos/roles ];

          flyingcircus.roles.memcached.enable = true;

          flyingcircus.enc.parameters = {
            location = "dev";
            production = true;
            resource_group = "test";
            interfaces.srv = {
              mac = "52:54:00:12:34:56";
              bridged = false;
              networks = {
                "192.168.101.0/24" = [ "192.168.101.2" ];
                "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::2" ];
              };
              gateways = {};
            };
          };
        };
  nodes.whqProdKernel =
        { pkgs, lib, ... }:
        {
          imports = [ ../nixos ../nixos/roles ];

          flyingcircus.roles.memcached.enable = true;

          flyingcircus.enc.parameters = {
            location = "whq";
            production = true;
            resource_group = "test";
            interfaces.srv = {
              mac = "52:54:00:12:34:56";
              bridged = false;
              networks = {
                "192.168.101.0/24" = [ "192.168.101.3" ];
                "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::3" ];
              };
              gateways = {};
            };
          };
        };
    nodes.rzobNonProdKernel =
          { pkgs, lib, ... }:
          {
            imports = [ ../nixos ../nixos/roles ];

            flyingcircus.roles.memcached.enable = true;

            flyingcircus.enc.parameters = {
              location = "rzob";
              production = false;
              resource_group = "test";
              interfaces.srv = {
                mac = "52:54:00:12:34:56";
                bridged = false;
                networks = {
                  "192.168.101.0/24" = [ "192.168.101.4" ];
                  "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::4" ];
                };
                gateways = {};
              };
            };
          };
  nodes.prodKernel =
    { pkgs, lib, ... }:
    {
      imports = [ ../nixos ../nixos/roles ];

      flyingcircus.useVerificationKernel = false;

      flyingcircus.roles.memcached.enable = true;

      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:34:56";
          bridged = false;
          networks = {
            "192.168.101.0/24" = [ "192.168.101.5" ];
            "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::5" ];
          };
          gateways = {};
        };
      };
    };
  nodes.verifyKernel =
    { pkgs, lib, ... }:
    {
      imports = [ ../nixos ../nixos/roles ];

      flyingcircus.useVerificationKernel = true;

      flyingcircus.roles.memcached.enable = true;

      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:34:56";
          bridged = false;
          networks = {
            "192.168.101.0/24" = [  "192.168.101.6" ];
            "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::6" ];
          };
          gateways = {};
        };
      };
    };
    nodes.devNonProdKernel =
          { pkgs, lib, ... }:
          {
            imports = [ ../nixos ../nixos/roles ];

            flyingcircus.roles.memcached.enable = true;

            flyingcircus.enc.parameters = {
              location = "dev";
              production = false;
              resource_group = "test";
              interfaces.srv = {
                mac = "52:54:00:12:34:56";
                bridged = false;
                networks = {
                  "192.168.101.0/24" = [ "192.168.101.7" ];
                  "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::7" ];
                };
                gateways = {};
              };
            };
          };
    nodes.whqNonProdKernel =
          { pkgs, lib, ... }:
          {
            imports = [ ../nixos ../nixos/roles ];

            flyingcircus.roles.memcached.enable = true;

            flyingcircus.enc.parameters = {
              location = "whq";
              production = false;
              resource_group = "test";
              interfaces.srv = {
                mac = "52:54:00:12:34:56";
                bridged = false;
                networks = {
                  "192.168.101.0/24" = [ "192.168.101.8" ];
                  "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::8" ];
                };
                gateways = {};
              };
            };
          };
  testScript = ''
    start_all()

    def assertKernelVersion(vm, expected):
        vm.wait_for_unit('memcached.service')
        vm.wait_for_open_port(11211)

        found = vm.execute("uname -r")[1].strip()
        if found != expected:
            uname_a = vm.execute("uname -a")[1]
            raise AssertionError(
              f"Expected: {expected}, found: {found}. uname -a: {uname_a}"
            )

    assert "${stableVersion}".startswith("5.15."), "Expecting a 5.15.x kernel as stable kernel"
    assertKernelVersion(verifyKernel, "6.11.0")
    assertKernelVersion(prodKernel, "${stableVersion}")
    assertKernelVersion(rzobProdKernel, "${stableVersion}")
    assertKernelVersion(rzobNonProdKernel, "6.11.0")
    assertKernelVersion(whqProdKernel, "6.11.0")
    assertKernelVersion(devProdKernel, "6.11.0")
    assertKernelVersion(whqNonProdKernel, "6.11.0")
    assertKernelVersion(devNonProdKernel, "6.11.0")

  '';
})
