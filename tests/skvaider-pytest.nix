import ./make-test-python.nix (
  { pkgs, testlib, ... }:
  let
    # Actual models used by the skvaider test fixtures. Pre-fetched into the
    # Nix store so the VM has no need for internet access. Two separate caches
    # are pre-populated from these paths:
    #
    #   1. /tmp/pytest-run/var/tests/models/ — used by inference/conftest.py
    #      prepare_model() fixture (slugs: gemma-e5420636, embeddinggemma-a3125072)
    #   2. /tmp/inference-models/ — used by the devenv-style inference backend
    #      at :8001 so download() skips the network at server startup
    gemmaGGUF = pkgs.fetchurl {
      url = "https://huggingface.co/unsloth/gemma-3-270m-it-GGUF/resolve/c90975dbd40c0c7b275fefaae758c3415c906238/gemma-3-270m-it-UD-Q4_K_XL.gguf?download=true";
      hash = "sha256-5UIGNuDL/uJAUf8i6XGTgKOpMgekcu2xjdDImpX274A=";
    };
    embeddinggemmaGGUF = pkgs.fetchurl {
      url = "https://huggingface.co/unsloth/embeddinggemma-300m-GGUF/resolve/main/embeddinggemma-300M-F32.gguf";
      hash = "sha256-oxJQchKPx20cHY0Z97CVx+O/vwBZTc+Ki9O8szSTXVc=";
    };

    # Config for the devenv-style inference backend at :8001.
    # models_dir is absolute so it is independent of the working directory.
    # llama_server is not overridden: PATH resolution via pkgs.llama-cpp in
    # environment.systemPackages is sufficient.
    inferenceConfig = pkgs.writeText "skvaider-inference-config.toml" ''
      models_dir = "/tmp/inference-models"

      [server]
      host = "127.0.0.1"
      port = 8001

      [logging]
      log_level = "DEBUG"
      log_dir = "/tmp/inference-logs"

      [[openai.models]]
      engine = "llama-server"
      id = "gemma"
      context_size = 4096
      port = 8100
      cmd_args = []
      max_requests = 21
      task = "chat"

      [[openai.models.files]]
      url = "https://huggingface.co/unsloth/gemma-3-270m-it-GGUF/resolve/c90975dbd40c0c7b275fefaae758c3415c906238/gemma-3-270m-it-UD-Q4_K_XL.gguf?download=true"
      hash = "e5420636e0cbfee24051ff22e9719380a3a93207a472edb18dd0c89a95f6ef80"

      [[openai.models]]
      engine = "llama-server"
      id = "embeddinggemma"
      task = "embedding"
      cmd_args = ["-ngl", "0"]
      port = 8101
      context_size = 4096

      [[openai.models.files]]
      url = "https://huggingface.co/unsloth/embeddinggemma-300m-GGUF/resolve/main/embeddinggemma-300M-F32.gguf"
      hash = "a3125072128fc76d1c1d8d19f7b095c7e3bfbf00594dcf8a8bd3bcb334935d57"
    '';
    # Minimal gateway config for app_factory() when running Chain A tests
    # (test_endpoints.py, test_openai_client.py).  The test_lifespan in
    # skvaider/conftest.py overrides backends/models at runtime; we only
    # need a syntactically valid file so app_factory() can read it.
    gatewayConfig = pkgs.writeText "skvaider-gateway-config.toml" ''
      [auth]

      [server]
      directory = "/tmp"

      [logging]
      log_dir = "/tmp"

      [[backend]]
      type = "skvaider"
      url = "http://127.0.0.1:8001"

      [[models]]
      id = "gemma"
      instances = 1
      memory = { ram = 1 }
      task = "chat"

      [[models]]
      id = "embeddinggemma"
      instances = 1
      memory = { ram = 1 }
      task = "embedding"
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
        environment.systemPackages = [ pkgs.llama-cpp ];
      };

    testScript = ''
      start_all()
      testnode.wait_for_unit("multi-user.target")

      with subtest("prepare model caches"):
          # pytest fixture cache — used by inference/conftest.py prepare_model()
          testnode.succeed(
              "mkdir -p /tmp/pytest-run/var/tests/models/gemma-e5420636 && "
              "ln -sf ${gemmaGGUF} "
              "    /tmp/pytest-run/var/tests/models/gemma-e5420636/gemma-3-270m-it-UD-Q4_K_XL.gguf && "
              "mkdir -p /tmp/pytest-run/var/tests/models/embeddinggemma-a3125072 && "
              "ln -sf ${embeddinggemmaGGUF} "
              "    /tmp/pytest-run/var/tests/models/embeddinggemma-a3125072/embeddinggemma-300M-F32.gguf"
          )

          # Inference server model cache — LlamaModel.download() checks
          # integrity_marker_file + model_files existence and skips the
          # download when both are present.  Pre-populating here prevents
          # any outbound network access from skvaider-inference at startup.
          testnode.succeed(
              "mkdir -p /tmp/inference-models/gemma-e5420636 && "
              "ln -sf ${gemmaGGUF} "
              "    /tmp/inference-models/gemma-e5420636/gemma-3-270m-it-UD-Q4_K_XL.gguf && "
              "touch /tmp/inference-models/gemma-e5420636/integrity.ok && "
              "mkdir -p /tmp/inference-models/embeddinggemma-a3125072 && "
              "ln -sf ${embeddinggemmaGGUF} "
              "    /tmp/inference-models/embeddinggemma-a3125072/embeddinggemma-300M-F32.gguf && "
              "touch /tmp/inference-models/embeddinggemma-a3125072/integrity.ok && "
              "mkdir -p /tmp/inference-logs"
          )

      with subtest("start inference backend at :8001"):
          # skvaider-inference reads its config via --config (argparse), not
          # an env var.  The uvicorn server inside main() re-reads sys.argv
          # for the same --config flag when the ASGI lifespan runs.
          testnode.succeed(
              "${pkgs.fc.skvaider.passthru.testEnv}/bin/skvaider-inference "
              "--config ${inferenceConfig} "
              "> /tmp/inference.log 2>&1 &"
          )
          testnode.wait_for_open_port(8001, timeout=60)
          testnode.wait_until_succeeds(
              "curl -sf http://127.0.0.1:8001/manager/health", timeout=30
          )

          # Explicitly load both models before pytest starts.  POST /models/{id}/load
          # blocks until llama-server is healthy, so by the time both curls
          # return the models are active and Chain A tests skip waiting entirely.
          testnode.succeed(
              "curl -sf -X POST http://127.0.0.1:8001/models/gemma/load && "
              "curl -sf -X POST http://127.0.0.1:8001/models/embeddinggemma/load",
              timeout=120
          )

      with subtest("skvaider pytest suite"):
          pytest = "${pkgs.fc.skvaider.passthru.testEnv}/bin/pytest"
          common = (
              "--override-ini=addopts= "
              "--override-ini=asyncio_mode=auto "
              "--override-ini=consider_namespace_packages=true "
              "-v --tb=short -p no:cacheprovider"
          )
          # Run inference tests in their own invocation so that
          # skvaider/inference/conftest.py is scoped correctly and does NOT
          # shadow the gateway 'client' fixture from skvaider/conftest.py.
          testnode.succeed(
              f"cd /tmp/pytest-run && {pytest} --pyargs skvaider.inference.tests {common}",
              timeout=600
          )
          # Run gateway + proxy + router tests.  Runs separately so the
          # inference conftest is not in scope and skvaider/conftest.py
          # provides the correct 'client' fixture (gateway app_factory).
          testnode.succeed(
              f"cd /tmp/pytest-run && SKVAIDER_CONFIG_FILE=${gatewayConfig} {pytest} --pyargs "
              "skvaider.tests skvaider.proxy.tests skvaider.routers.tests "
              f"{common}",
              timeout=600
          )
    '';
  }
)
