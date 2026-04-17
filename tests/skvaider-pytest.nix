import ./make-test-python.nix (
  {
    pkgs,
    testlib,
    testOpts ? "",
    ...
  }:
  let
    # GGUFs pre-fetched into the Nix store — the VM has no internet access.
    # Two caches are pre-populated from these paths:
    #   1. /tmp/pytest-run/var/tests/models/ — inference/conftest.py prepare_model()
    #   2. /tmp/inference-models/           — inference backend at :8001
    gemmaGGUF = pkgs.fetchurl {
      url = "https://huggingface.co/unsloth/gemma-3-270m-it-GGUF/resolve/c90975dbd40c0c7b275fefaae758c3415c906238/gemma-3-270m-it-UD-Q4_K_XL.gguf?download=true";
      hash = "sha256-5UIGNuDL/uJAUf8i6XGTgKOpMgekcu2xjdDImpX274A=";
    };
    embeddinggemmaGGUF = pkgs.fetchurl {
      url = "https://huggingface.co/unsloth/embeddinggemma-300m-GGUF/resolve/main/embeddinggemma-300M-F32.gguf";
      hash = "sha256-oxJQchKPx20cHY0Z97CVx+O/vwBZTc+Ki9O8szSTXVc=";
    };

    # Config files live in the skvaider source alongside the devenv configs.
    # inferenceConfig mirrors config-inference-1.toml with absolute /tmp paths.
    # gatewayConfig is a minimal single-backend variant of config.toml.
    src = pkgs.fc.skvaider.passthru.src;
    inferenceConfig = pkgs.runCommand "config-inference-test.toml" { } ''
      cat ${src}/nix/config-inference-test.toml > $out
      echo 'embedding_verification_file = "${src}/embeddings-reference.json"' >> $out
    '';
    gatewayConfig = "${src}/nix/config-gateway-test.toml";

    testEnv = pkgs.fc.skvaider.passthru.testEnv;

    runTestsScript = pkgs.writeShellScriptBin "run-tests" ''
      set -euo pipefail

      export PYTHONUNBUFFERED=1
      export SKVAIDER_CONFIG_FILE=${gatewayConfig}

      # Run from /tmp/pytest-run: the inference/conftest.py prepare_model()
      # fixture resolves its model cache as var/tests/models/ relative to cwd,
      # and the init service pre-populates /tmp/pytest-run/var/tests/models/.
      cd /tmp/pytest-run
      ${testEnv}/bin/pytest -c ${src}/pytest.ini --rootdir=${src} --import-mode=importlib -p no:cacheprovider --ignore=${src}/src/aramaki ${src}/src/ -v -s --tb=short "$@"
    '';
  in
  {
    name = "skvaider-pytest";

    nodes.testnode =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        imports = [ (testlib.fcConfig { id = 1; }) ];
        networking.domain = "fcio.net";
        virtualisation.memorySize = 4096;

        environment.systemPackages = [
          pkgs.llama-cpp
          runTestsScript
        ];

        # Populate both model caches from the Nix store before any service starts.
        # This is a oneshot so it runs exactly once and the inference service
        # can declare After/Requires on it instead of doing setup inline.
        systemd.services.skvaider-test-init = {
          description = "Populate skvaider test model caches";
          wantedBy = [ "multi-user.target" ];
          before = [ "skvaider-inference-test.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            # pytest fixture cache — used by inference/conftest.py prepare_model()
            mkdir -p /tmp/pytest-run/var/tests/models/gemma-e5420636
            ln -sf ${gemmaGGUF} \
              /tmp/pytest-run/var/tests/models/gemma-e5420636/gemma-3-270m-it-UD-Q4_K_XL.gguf
            mkdir -p /tmp/pytest-run/var/tests/models/embeddinggemma-a3125072
            ln -sf ${embeddinggemmaGGUF} \
              /tmp/pytest-run/var/tests/models/embeddinggemma-a3125072/embeddinggemma-300M-F32.gguf

            # Inference server model cache — LlamaModel.download() checks
            # integrity_marker_file + model_files existence and skips the
            # download when both are present.  Pre-populating here prevents
            # any outbound network access from skvaider-inference at startup.
            mkdir -p /tmp/inference-models/gemma-e5420636
            ln -sf ${gemmaGGUF} \
              /tmp/inference-models/gemma-e5420636/gemma-3-270m-it-UD-Q4_K_XL.gguf
            touch /tmp/inference-models/gemma-e5420636/integrity.ok
            mkdir -p /tmp/inference-models/embeddinggemma-a3125072
            ln -sf ${embeddinggemmaGGUF} \
              /tmp/inference-models/embeddinggemma-a3125072/embeddinggemma-300M-F32.gguf
            touch /tmp/inference-models/embeddinggemma-a3125072/integrity.ok
            mkdir -p /tmp/inference-logs
          '';
        };

        systemd.services.skvaider-inference-test = {
          description = "skvaider inference backend for pytest VM test";
          wantedBy = [ "multi-user.target" ];
          requires = [ "skvaider-test-init.service" ];
          after = [ "skvaider-test-init.service" ];
          path = [ pkgs.llama-cpp ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${testEnv}/bin/skvaider-inference --config ${inferenceConfig}";
            StandardOutput = "append:/tmp/inference.log";
            StandardError = "append:/tmp/inference.log";
          };
        };
      };

    testScript = ''
      start_all()
      testnode.wait_for_unit("skvaider-inference-test.service")
      testnode.wait_until_succeeds("curl -sf http://127.0.0.1:8001/manager/health", timeout=60)
      # PATCH /manager/manifest triggers async model loading; poll until both are active (running + healthy).
      testnode.succeed(
          "curl -sf -X PATCH http://127.0.0.1:8001/manager/manifest"
          " -H 'Content-Type: application/json'"
          " -d '{\"models\":[\"gemma\",\"embeddinggemma\"],\"serial\":[\"00000-00000\",1]}'",
          timeout=10,
      )
      testnode.wait_until_succeeds(
          "h=$(curl -sf http://127.0.0.1:8001/manager/health); echo $h;"
          " echo $h | python3 -c \"import sys,json; d=json.load(sys.stdin);"
          " [print(m['id'], sorted(m['status'])) for m in d['models']];"
          " statuses={m['id']:set(m['status']) for m in d['models']};"
          " assert 'active' in statuses.get('gemma',set()) and 'active' in statuses.get('embeddinggemma',set())\"",
          timeout=600,
      )

      with subtest("Run tests"):
          testnode.succeed("run-tests ${testOpts}", timeout=30 * 60)
    '';
  }
)
