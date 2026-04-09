import ./make-test-python.nix (
  { pkgs, testlib, ... }:
  let
    modelServerIp = testlib.fcIP.srv4 1;
    gatewayIp = testlib.fcIP.srv4 2;

    nixpkgs-unstable = import (pkgs.fetchFromGitHub {
      owner = "NixOS";
      repo = "nixpkgs";
      rev = "0182a361324364ae3f436a63005877674cf45efb";
      hash = "sha256-0NBlEBKkN3lufyvFegY4TYv5mCNHbi5OmBDrzihbBMQ=";
    }) { };

    vllm-cpu = nixpkgs-unstable.vllm;

    tiny-gpt2 =
      let
        fetch =
          name: sha256:
          pkgs.fetchurl {
            url = "https://huggingface.co/sshleifer/tiny-gpt2/resolve/main/${name}";
            inherit sha256;
          };
      in
      pkgs.runCommand "tiny-gpt2" { } ''
        mkdir $out
        cp ${fetch "config.json" "1c20ncwg0nxyq0b5bmqs92s9i3rrgkly0qawky9bmgis1j1ykabp"} $out/config.json
        cp ${fetch "tokenizer_config.json" "07wk83wkzd6ykm6y8xzy6ipwh5b6dcm6rqs2199q659sdrhfn12y"} $out/tokenizer_config.json
        cp ${fetch "vocab.json" "09rgyz8xllry92darghnji34rnyjhzkl6ykwdsv1iikhpi9ph203"} $out/vocab.json
        cp ${fetch "merges.txt" "1idd4rvkpqqbks51i2vjbd928inw7slij9l4r063w3y5fd3ndq8w"} $out/merges.txt
        cp ${fetch "pytorch_model.bin" "1rh4bk5fqjy74k5r1dwmm6ax40fj0djapmfycpkxyaq36i0b41mp"} $out/pytorch_model.bin
      '';
  in
  {
    name = "skvaider";

    nodes.model =
      {
        pkgs,
        lib,
        config,
        ...
      }:
      {
        imports = [ (testlib.fcConfig { id = 1; }) ];
        networking.domain = "fcio.net";
        virtualisation.memorySize = 3072;
        # The fc-nixos resource-group firewall only allows source IPs listed in
        # encAddresses. Without this, the gateway's connections to :8000 are
        # refused by iptables (refused connection logged on ethsrv).
        flyingcircus.encAddresses = [
          {
            name = "gateway";
            ip = gatewayIp;
          }
        ];

        flyingcircus.roles.ai-model-server.enable = true;
        flyingcircus.roles.ai-model-server.skvaider-inference.hf_token = "";
        flyingcircus.roles.ai-model-server.skvaider-inference.enable = true;

        systemd.services.skvaider-inference.path = lib.mkAfter [ vllm-cpu ];

        flyingcircus.roles.ai-model-server.skvaider-inference.settings = {
          # Explicitly carry all required fields: our attrset at normal priority
          # fully supersedes the lib.mkDefault block in the module, so any key
          # the module sets via mkDefault that we do not repeat here will be absent
          # from the generated TOML, causing Pydantic validation failures at startup.
          models_dir = "/var/lib/skvaider/model";
          server.host = "0.0.0.0";
          server.port = 8000;
          openai.models = [
            {
              id = "tiny-gpt2";
              task = "chat";
              engine = "vllm";
              repo = "${tiny-gpt2}";
              revision = "main";
              context_size = 128;
              max_requests = 1;
              port = 8001;
              cmd_args = [
                "--device"
                "cpu"
              ];
            }
          ];
        };
      };

    nodes.gateway =
      {
        pkgs,
        lib,
        config,
        ...
      }:
      {
        imports = [
          (testlib.fcConfig {
            id = 2;
            extraEncParameters.secret_salt = "testsalt";
          })
        ];
        networking.domain = "fcio.net";

        flyingcircus.roles.ai-api-gateway.enable = true;
        flyingcircus.enc.name = "gateway";
        flyingcircus.encServices = [
          {
            address = modelServerIp;
            ips = [ modelServerIp ];
            location = "test";
            password = "testpass";
            service = "ai-model-server-server";
          }
        ];
        flyingcircus.roles.ai-api-gateway.settings = {
          auth.static_tokens = [ "testtoken" ];
          # server.directory must be explicit: the Python default is Path(".") and
          # systemd's working directory is /, so the debug middleware would try to
          # mkdir /debug which the skvaider user cannot write.
          server.directory = "/var/lib/skvaider";
          # Tell the gateway about the model so pool.model_configs is populated
          # and the semaphore + placement logic can function.
          models = [
            {
              id = "tiny-gpt2";
              instances = 1;
              # No GPU/RAM limits needed for this CPU-only test model.
              memory = { };
              task = "chat";
            }
          ];
        };
        environment.etc."nixos/enc.json".text = builtins.toJSON config.flyingcircus.enc;
      };

    testScript = ''
      start_all()

      model.wait_for_unit("multi-user.target")
      gateway.wait_for_unit("multi-user.target")

      with subtest("network connectivity"):
          gateway.succeed("ping -c1 ${modelServerIp}")
          model.succeed("ping -c1 ${gatewayIp}")

      with subtest("gateway discovers model server"):
          gateway.wait_for_unit("skvaider-config.service")
          gateway.wait_for_file("/var/lib/skvaider/config.toml")
          gateway.succeed("grep '${modelServerIp}:8000' /var/lib/skvaider/config.toml")
          gateway.succeed(
              "${pkgs.lib.getExe' pkgs.fc.skvaider "check-skvaider-config"} /var/lib/skvaider/config.toml"
          )

      with subtest("skvaider-inference starts and serves"):
          model.wait_for_unit("skvaider-inference.service")
          model.wait_for_open_port(8000)

      with subtest("inference api responds"):
          model.succeed("curl -sf http://localhost:8000/models")

      with subtest("inference through gateway"):
          # The gateway must connect to the inference server, discover the model,
          # trigger a load (which starts vllm), and mark it active before it can
          # proxy requests.  Give vllm up to 5 minutes to start on this slow VM.
          gateway.wait_for_unit("skvaider.service")
          gateway.wait_for_open_port(23211)
          gateway.wait_until_succeeds(
              "curl -sf -X POST http://127.0.0.1:23211/openai/v1/completions"
              " -H 'Authorization: Bearer testtoken'"
              " -H 'Content-Type: application/json'"
              " -d '{\"model\": \"tiny-gpt2\", \"prompt\": \"Hello\", \"max_tokens\": 5}'",
              timeout=300
          )

      with subtest("skvaider pytest suite"):
          gateway.succeed("cp -r ${pkgs.fc.skvaider.passthru.src} /tmp/skvaider-src")
          gateway.succeed("chmod -R u+w /tmp/skvaider-src")
          gateway.succeed(
              "cd /tmp/skvaider-src && "
              "${pkgs.fc.skvaider.passthru.testEnv}/bin/pytest src/skvaider/ "
              "--override-ini=addopts= -v --tb=short -p no:cacheprovider",
              timeout=300
          )
    '';
  }
)
