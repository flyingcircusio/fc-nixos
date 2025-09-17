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

        environment.systemPackages = [
          (pkgs.writers.writePython3Bin "check-skavider-config" { } ''
            import tomllib
            with open("/var/lib/skvaider/config.toml", "rb") as f:
                data = tomllib.load(f)
            assert data['backend'] == [{
                "type": "openai",
                "url": "http://host1.fcio.net:11434"
            }]
            assert data['aramaki']['secret_salt'] == "mysecretpepper"
          '')
        ];
      };
    testScript = ''
      import tomllib
      machine.wait_for_unit("skvaider-config.service")
      machine.wait_for_file("/var/lib/skvaider/config.toml")
      machine.succeed("check-skavider-config")
    '';
  }
)
