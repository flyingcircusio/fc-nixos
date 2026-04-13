import ./make-test-python.nix (
  { pkgs, testlib, ... }:
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
    inferenceConfig = "${src}/nix/config-inference-test.toml";
    gatewayConfig = "${src}/nix/config-gateway-test.toml";
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
          python = "${pkgs.fc.skvaider.passthru.testEnv}/bin/python3"
          common = (
              "--override-ini=addopts= "
              "--override-ini=asyncio_mode=auto "
              "--override-ini=consider_namespace_packages=true "
              "-v --tb=short -p no:cacheprovider"
          )
          # 1. Inference tests in their own process: scopes
          #    skvaider/inference/conftest.py locally so it does NOT shadow
          #    the gateway 'client' fixture in a subsequent pytest session.
          testnode.succeed(
              f"cd /tmp/pytest-run && {pytest} --pyargs skvaider.inference.tests {common}",
              timeout=600
          )
          # 2. Gateway tests in their own process: skvaider/inference/conftest.py
          #    is not imported; skvaider/conftest.py 'client' is used correctly.
          #    SKVAIDER_CONFIG_FILE gives app_factory() a valid config to parse.
          testnode.succeed(
              f"cd /tmp/pytest-run && SKVAIDER_CONFIG_FILE=${gatewayConfig} "
              f"{pytest} --pyargs skvaider.tests {common}",
              timeout=600
          )
          # 3. Proxy + router unit tests via filesystem paths (no __init__.py in
          #    those test dirs so --pyargs dotted names don't work for them).
          #    These tests use only DummyBackend fixtures; no client/app_factory.
          testnode.succeed(
              f"pkg=$({python} -c 'import skvaider,os; print(os.path.dirname(skvaider.__file__))') && "
              f"cd /tmp/pytest-run && {pytest} $pkg/proxy/tests $pkg/routers/tests {common}",
              timeout=120
          )
    '';
  }
)
