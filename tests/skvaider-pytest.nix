import ./make-test-python.nix (
  { pkgs, testlib, ... }:
  let
    # SmolLM2-135M-Instruct-Q4_K_M.gguf — a real 90 MB chat GGUF used in place
    # of the 270 MB upstream gemma GGUF.  The gemma() fixture in
    # inference/conftest.py reads SKVAIDER_TEST_GEMMA_URL / SKVAIDER_TEST_GEMMA_HASH
    # at startup; we point those at a local HTTP server backed by this store path
    # so the download succeeds without internet access.
    #
    # To update: nix-prefetch-url --type sha256 <url>  (base32 → SRI via nix hash to-sri)
    # smolLMHexHash is sha256sum of the file (what LlamaModelFile.hash expects).
    smolLM = pkgs.fetchurl {
      url = "https://huggingface.co/bartowski/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q4_K_M.gguf";
      hash = "sha256-LoBAzq54Favg3LNUC5mV6qH6DSyp55fQpjWuRDPGjC0=";
    };
    smolLMHexHash = "2e8040ceae7815abe0dcb3540b9995eaa1fa0d2ca9e797d0a635ae4433c68c2d";
    smolLMFilename = "SmolLM2-135M-Instruct-Q4_K_M.gguf";
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
      };

    testScript = ''
      start_all()
      testnode.wait_for_unit("multi-user.target")

      with subtest("skvaider pytest suite"):
          # Serve SmolLM2-135M-Instruct-Q4_K_M.gguf from a local HTTP server.
          # The gemma_model_file fixture reads SKVAIDER_TEST_GEMMA_URL / _HASH to
          # substitute a locally-served GGUF for the default 270 MB gemma download.
          # This unblocks all Chain-B tests that register a model without starting
          # llama-server (test_proxy, test_main usage, test_metrics, test_manager
          # download, test_model_name_case_normalization).
          testnode.succeed(
              "mkdir -p /tmp/gguf-serve && "
              "ln -sf ${smolLM} /tmp/gguf-serve/${smolLMFilename} && "
              "python3 -m http.server 9999 --directory /tmp/gguf-serve &"
          )
          testnode.wait_for_open_port(9999)

          testnode.succeed(
              "mkdir -p /tmp/pytest-run && "
              "pkg=$(${pkgs.fc.skvaider.passthru.testEnv}/bin/python3 -c "
              "'import skvaider,os; print(os.path.dirname(skvaider.__file__))') && "
              "cd /tmp/pytest-run && "
              "SKVAIDER_TEST_GEMMA_URL='http://127.0.0.1:9999/${smolLMFilename}' "
              "SKVAIDER_TEST_GEMMA_HASH='${smolLMHexHash}' "
              "${pkgs.fc.skvaider.passthru.testEnv}/bin/pytest --pyargs skvaider "
              "--override-ini=addopts= "
              "--override-ini=asyncio_mode=auto "
              "--override-ini=consider_namespace_packages=true "
              # Chain A: no devenv inference backend at :8001 in this VM.
              "--ignore=$pkg/tests/test_endpoints.py "
              "--ignore=$pkg/tests/test_openai_client.py "
              "--ignore=$pkg/tests/test_model_management.py "
              # test_stability uses embeddinggemma (300 MB GGUF); no override provided.
              "--ignore=$pkg/inference/tests/test_stability.py "
              # The three remaining exclusions need llama-server to actually run:
              #   test_health               → await gemma.start() → llama-server
              #   test_manager_start_crash  → manager.start_model() → llama-server
              #   test_manager_start_model  → full start + completion roundtrip
              "--deselect inference/tests/test_main.py::test_health "
              "--deselect inference/tests/test_manager.py::test_manager_start_crash_quick_return "
              "--deselect inference/tests/test_manager.py::test_manager_start_model "
              "-v --tb=short -p no:cacheprovider",
              timeout=600
          )
    '';
  }
)
