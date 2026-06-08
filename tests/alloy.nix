import ./make-test-python.nix (
  {
    testlib,
    pkgs,
    ...
  }:
  {
    name = "alloy";
    nodes.alloy =
      {
        lib,
        pkgs,
        ...
      }:
      {
        imports = [
          ../nixos
          ../nixos/roles
          (testlib.fcConfig { net.fe = false; })
        ];
        flyingcircus.roles.loki = {
          enable = true;
          storageSchedule.default = lib.mkForce [
            {
              startDate = "2024-09-10";
              backend = "filesystem";
            }
          ];
        };

        flyingcircus.encServices = [
          {
            address = "alloy.gocept.net"; # gocept.net due to PL-133063
            service = "loki-collector";
            ips = [
              (testlib.fcIP.srv4 1)
              (testlib.fcIP.srv6 1)
            ];
          }
        ];
      };

    testScript =
      { nodes, ... }:
      ''
        alloy.wait_for_unit("alloy.service")
      '';
  }
)
