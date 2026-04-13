import ./make-test-python.nix (
  { pkgs, testlib, ... }:
  let
    # Actual models used by the skvaider test fixtures. Pre-fetched into the
    # Nix store so the VM has no need for internet access. The models_cache
    # fixture (inference/conftest.py) is pre-populated with symlinks to these
    # store paths; prepare_model() then skips the download entirely.
    #
    # Slugs are derived from LlamaModelFile.hash[:8] in inference/conftest.py:
    #   gemma         → gemma-e5420636
    #   embeddinggemma → embeddinggemma-a3125072
    gemmaGGUF = pkgs.fetchurl {
      url = "https://huggingface.co/unsloth/gemma-3-270m-it-GGUF/resolve/c90975dbd40c0c7b275fefaae758c3415c906238/gemma-3-270m-it-UD-Q4_K_XL.gguf?download=true";
      hash = "sha256-5UIGNuDL/uJAUf8i6XGTgKOpMgekcu2xjdDImpX274A=";
    };
    embeddinggemmaGGUF = pkgs.fetchurl {
      url = "https://huggingface.co/unsloth/embeddinggemma-300m-GGUF/resolve/main/embeddinggemma-300M-F32.gguf";
      hash = "sha256-oxJQchKPx20cHY0Z97CVx+O/vwBZTc+Ki9O8szSTXVc=";
    };
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

      with subtest("skvaider pytest suite"):
          # Pre-populate the models_cache so prepare_model() never hits the
          # network. The cache path is CWD-relative (var/tests/models/) so we
          # run pytest from /tmp/pytest-run throughout.
          testnode.succeed(
              "mkdir -p /tmp/pytest-run/var/tests/models/gemma-e5420636 && "
              "ln -sf ${gemmaGGUF} "
              "    /tmp/pytest-run/var/tests/models/gemma-e5420636/gemma-3-270m-it-UD-Q4_K_XL.gguf && "
              "mkdir -p /tmp/pytest-run/var/tests/models/embeddinggemma-a3125072 && "
              "ln -sf ${embeddinggemmaGGUF} "
              "    /tmp/pytest-run/var/tests/models/embeddinggemma-a3125072/embeddinggemma-300M-F32.gguf"
          )

          testnode.succeed(
              "pkg=$(${pkgs.fc.skvaider.passthru.testEnv}/bin/python3 -c "
              "'import skvaider,os; print(os.path.dirname(skvaider.__file__))') && "
              "cd /tmp/pytest-run && "
              "${pkgs.fc.skvaider.passthru.testEnv}/bin/pytest --pyargs skvaider "
              "--override-ini=addopts= "
              "--override-ini=asyncio_mode=auto "
              "--override-ini=consider_namespace_packages=true "
              # Chain A: no devenv inference backend at :8001 in this VM.
              "--ignore=$pkg/tests/test_endpoints.py "
              "--ignore=$pkg/tests/test_openai_client.py "
              "--ignore=$pkg/tests/test_model_management.py "
              # test_manager_start_model: hardcoded model-metadata assertions
              # (n_ctx_train, n_embd, n_params, size) specific to the gemma
              # checkpoint; also runs a 1000-token completion on CPU.
              "--deselect inference/tests/test_manager.py::test_manager_start_model "
              "-v --tb=short -p no:cacheprovider",
              timeout=900
          )
    '';
  }
)
