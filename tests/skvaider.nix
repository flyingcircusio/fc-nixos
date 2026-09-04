import ./make-test-python.nix (
  { pkgs, testlib, ... }:
  let
    modelServerIp = testlib.fcIP.srv4 1;
    gatewayIp = testlib.fcIP.srv4 2;

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

    fakeNvidiaOk = pkgs.writeShellScriptBin "nvidia-smi" ''
      case "$*" in
        *"-q -x"*) printf '%s\n' '<nvidia_smi_log><gpu><gpu_recovery_action>None</gpu_recovery_action></gpu></nvidia_smi_log>' ;;
        *) printf '%s\n' '0, GPU-healthy, 16 W, 31, 0 %' ;;
      esac
    '';

    fakeNvidiaReset = pkgs.writeShellScriptBin "nvidia-smi" ''
      case "$*" in
        *"-q -x"*) printf '%s\n' '<nvidia_smi_log><gpu><gpu_recovery_action>Reset</gpu_recovery_action></gpu></nvidia_smi_log>' ;;
        *) printf '%s\n' '0, GPU-reset, 16 W, 31, 0 %' ;;
      esac
    '';

    fakeNvidiaNa = pkgs.writeShellScriptBin "nvidia-smi" ''
      case "$*" in
        *"-q -x"*) printf '%s\n' '<nvidia_smi_log><gpu><gpu_recovery_action>None</gpu_recovery_action></gpu></nvidia_smi_log>' ;;
        *) printf '%s\n' '0, GPU-bad, [N/A], ERR!, 0 %' ;;
      esac
    '';

    # All functional assertions run inside this script on the gateway node.
    # The testScript handles only cross-node readiness ordering (wait_for_unit,
    # wait_for_open_port) before invoking this.
    runTestsScript = pkgs.writeShellScriptBin "run-tests" ''
      set -exuo pipefail

      # gateway ↔ model network connectivity
      ping -c1 ${modelServerIp}

      cat /var/lib/skvaider/config.toml

      # gateway has discovered the model server and written its config
      grep '${modelServerIp}:8000' /var/lib/skvaider/config.toml
      ${pkgs.lib.getExe' pkgs.fc.skvaider "check-skvaider-config"} \
        /var/lib/skvaider/config.toml

      # inference API is reachable from gateway
      curl -v -sf http://${modelServerIp}:8000/manager/health

      # gateway proxies model list through to a bearer-authenticated caller
      curl -sf http://127.0.0.1:23211/openai/v1/models \
        -H 'Authorization: Bearer testtoken' \
        | python3 -c "
      import sys, json
      d = json.load(sys.stdin)
      assert any(m['id'] == 'tiny-gpt2' for m in d['data']), \
          f'tiny-gpt2 not in model list: {d}'
      "
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

        # qemu-vm.nix overrides videoDrivers to "modesetting" for VM builds,
        # so the nvidia-container-toolkit driver assertion cannot see the
        # role's services.xserver.videoDrivers = [ "nvidia" ] here.
        hardware.nvidia-container-toolkit.suppressNvidiaDriverAssertion = true;

        systemd.services.skvaider-inference.path = lib.mkAfter [ pkgs.vllm ];

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
              cmd_args = [ ];
            }
          ];
        };

        flyingcircus.services.sensu-client.enable = true;
        flyingcircus.services.sensu-client.server = "sensu.example.invalid";
        flyingcircus.services.sensu-client.password = "testpass";
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

        environment.systemPackages = [ runTestsScript ];

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
          auth.admin_tokens = [ "testtoken" ];
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
              # memory must name at least one resource so fit_score() is non-zero.
              # The inference manager always exposes a RAMMonitor, so 'ram' is
              # always reported; 1 byte means no real constraint in practice.
              memory = {
                ram = 1;
              };
              task = "chat";
            }
          ];
        };
        environment.etc."nixos/enc.json".text = builtins.toJSON config.flyingcircus.enc;
      };

    testScript = ''
      start_all()

      # Wait for both nodes to be fully up before running any tests.
      model.wait_for_unit("multi-user.target")
      gateway.wait_for_unit("multi-user.target")

      # Wait for skvaider services to be ready before handing off to run-tests.
      gateway.wait_for_unit("skvaider-config.service")
      gateway.wait_for_file("/var/lib/skvaider/config.toml")
      model.wait_for_unit("skvaider-inference.service")
      model.wait_for_open_port(8000)
      gateway.wait_for_unit("skvaider.service")
      gateway.wait_for_open_port(23211)
      gateway.wait_until_succeeds(
          "curl -sf http://127.0.0.1:23211/openai/v1/models"
          " -H 'Authorization: Bearer testtoken'",
          timeout=120,
      )

      with subtest("NVIDIA health checks should detect reset/N/A state"):
          checks = model.succeed("sensu-client-show-config")
          assert "nvidia_gpu_reset_required" in checks, checks
          assert "nvidia_gpu_smi_sane" in checks, checks

          model.succeed(
              "sensu-client-show-config | python3 -c 'import json, sys; print(json.load(sys.stdin)[\"checks\"][\"nvidia_gpu_reset_required\"][\"command\"])' > /tmp/check-nvidia-reset-required && "
              "sensu-client-show-config | python3 -c 'import json, sys; print(json.load(sys.stdin)[\"checks\"][\"nvidia_gpu_smi_sane\"][\"command\"])' > /tmp/check-nvidia-smi-sane"
          )
          model.succeed("NVIDIA_SMI=${fakeNvidiaOk}/bin/nvidia-smi sh /tmp/check-nvidia-reset-required")
          model.succeed("NVIDIA_SMI=${fakeNvidiaOk}/bin/nvidia-smi sh /tmp/check-nvidia-smi-sane")
          model.fail("NVIDIA_SMI=${fakeNvidiaReset}/bin/nvidia-smi sh /tmp/check-nvidia-reset-required")
          model.fail("NVIDIA_SMI=${fakeNvidiaNa}/bin/nvidia-smi sh /tmp/check-nvidia-smi-sane")

      with subtest("Run tests"):
          gateway.succeed("run-tests", timeout=120)
    '';
  }
)
