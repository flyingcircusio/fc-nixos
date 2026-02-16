import ./make-test-python.nix (
  { pkgs, testlib, ... }:
  let
  in
  {
    name = "ai-api-gateway";
    nodes.machine =
      {
        pkgs,
        lib,
        config,
        ...
      }:
      {
        imports = [
          (testlib.fcConfig {
            id = 1;
            extraEncParameters = {
              secret_salt = "mysecretpepper";
            };
          })
        ];
        networking.domain = "fcio.net";
        flyingcircus.roles.ai-api-gateway.enable = true;
        flyingcircus.enc.name = "testvm";
        flyingcircus.encServices = [
          {
            address = "host1.fcio.net";
            ips = [ "172.16.48.12" ];
            location = "whq";
            password = "abc";
            service = "ai-model-server-server";
          }
        ];
        environment.etc."nixos/enc.json".text = builtins.toJSON config.flyingcircus.enc;
      };
    testScript = ''
      import tomllib
      machine.wait_for_unit("skvaider-config.service")
      machine.wait_for_file("/var/lib/skvaider/config.toml")
      machine.succeed(
          "${pkgs.lib.getExe' pkgs.fc.skvaider "check-skvaider-config"} /var/lib/skvaider/config.toml"
      )
    '';
  }
)
