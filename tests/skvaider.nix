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
          # Check the gateway can reach the model server and discover the model.
          # We do not trigger a full model load (which requires vllm/llama-server
          # to run) because that is too slow and environment-dependent for CI.
          # Checking /openai/v1/models is sufficient to validate the gateway↔
          # inference-server plumbing: health check, model discovery, pool state.
          gateway.wait_for_unit("skvaider.service")
          gateway.wait_for_open_port(23211)
          gateway.wait_until_succeeds(
              "curl -sf http://127.0.0.1:23211/openai/v1/models"
              " -H 'Authorization: Bearer testtoken'"
              " | python3 -c \"import sys,json; d=json.load(sys.stdin); assert any(m['id']=='tiny-gpt2' for m in d['data'])\"",
              timeout=120
          )

      with subtest("skvaider pytest suite"):
          # Run against the installed package via --pyargs to avoid
          # ImportPathMismatchError: copying source to /tmp while the
          # testEnv already has skvaider installed causes pytest to find
          # the same module at two different paths.
          #
          # The skvaider pytest.ini (not in the Nix store) sets these four
          # options that we must reproduce explicitly:
          #   addopts       - stripped: contains coverage flags not needed here
          #   asyncio_mode  - auto: all async tests use implicit asyncio marks
          #   consider_namespace_packages - true: proxy/tests/ has no __init__.py,
          #                  so without this pytest 8.1+ can't import those files
          #                  as package-relative modules and relative imports fail
          #   junit_family  - legacy: minor XML output format, skipped here
          #
          # Two blocking chains prevent the excluded tests from running in the VM:
          #
          # Chain A — devenv backend (:8001 not present in VM):
          #   conftest.py:137  url = 'http://127.0.0.1:8001'  # hardcoded
          #   conftest.py:138  await backend_connection_is_up(url)  # hangs/errors
          #   conftest.py:319  client = TestClient(app_factory(lifespan=test_lifespan))
          #   conftest.py:332  openai_client depends on client (second hop)
          #
          # Chain B — HuggingFace download (no internet in VM):
          #   inference/conftest.py:166  if not cache_dir.exists(): await model.download()
          #   inference/model.py:441     httpx.AsyncClient GET to huggingface.co URL
          #   The persistent cache (var/tests/models/) is always empty in a fresh VM.
          #   inference/conftest.py:22   client(manager, gemma) — gemma is a fixture dep;
          #                              model.download() fires during fixture setup,
          #                              before the test body runs.
          #
          # --- File-level ignores ---
          #
          # tests/test_endpoints.py (8 tests)
          #   All use `client` fixture → Chain A.
          #
          # tests/test_openai_client.py (7 tests)
          #   All use `openai_client` → `client` → Chain A (two hops).
          #
          # tests/test_model_management.py (1 test: test_backend_model_warmup)
          #   Direct Chain A: test body itself hardcodes url='http://127.0.0.1:8001'
          #   and calls backend_connection_is_up(url) before touching any fixture.
          #
          # inference/tests/test_stability.py (1 test: test_embeddinggemma_output_stability)
          #   Uses `embeddinggemma` fixture → prepare_model() → Chain B.
          #   embeddinggemma-300M-F32.gguf (~300 MB) from huggingface.
          #
          # inference/tests/test_main.py (3 tests)
          #   test_health, test_usage_returns_ram_structure,
          #   test_usage_reflects_monitor_values
          #   All use inference `client(manager, gemma)` → Chain B via gemma dep.
          #
          # inference/tests/test_proxy.py (2 tests)
          #   test_proxy_returns_540_when_model_unavailable,
          #   test_proxy_returns_540_when_model_inactive
          #   Both use inference `client` → Chain B.
          #   Note: test_proxy_returns_540_* does not need the model started — only
          #   registered — but `client`'s gemma dependency triggers download anyway.
          #
          # --- Individual deselects in otherwise-passing files ---
          #
          # inference/tests/test_manager.py::test_manager_start_crash_quick_return
          #   Uses `gemma` directly → Chain B.
          #
          # inference/tests/test_manager.py::test_download_model_success
          #   Uses `gemma` directly; test body also calls gemma.download() explicitly
          #   (line 21), but fixture setup is the first blocker → Chain B.
          #
          # inference/tests/test_manager.py::test_manager_start_model
          #   Uses `gemma` directly; also calls manager.start_model() which runs
          #   llama-server — not in test VM either. Primary block: Chain B.
          #
          # inference/tests/test_metrics.py::{test_metrics_endpoint_returns_prometheus_format,
          #   test_proxy_unavailable_increments_counter,
          #   test_metrics_content_type_is_prometheus,
          #   test_metrics_includes_memory_bytes_after_monitor_update}
          #   All use inference `client` (or `client` + explicit `gemma`) → Chain B.
          #   The other 7 tests in this file (test_record_usage_*, test_extract_*)
          #   have no network deps and pass.
          #
          # inference/tests/test_model_name_case_normalization.py::
          #   test_inference_endpoints_normalize_model_name
          #   Uses inference `client` + explicit `gemma` → Chain B.
          #   test_model_config_normalizes_id_to_lowercase in the same file has no
          #   network dep and passes.
          gateway.succeed(
              "pkg=$(${pkgs.fc.skvaider.passthru.testEnv}/bin/python3 -c "
              "'import skvaider,os; print(os.path.dirname(skvaider.__file__))') && "
              "${pkgs.fc.skvaider.passthru.testEnv}/bin/pytest --pyargs skvaider "
              "--override-ini=addopts= "
              "--override-ini=asyncio_mode=auto "
              "--override-ini=consider_namespace_packages=true "
              "--ignore=$pkg/tests/test_endpoints.py "
              "--ignore=$pkg/tests/test_openai_client.py "
              "--ignore=$pkg/tests/test_model_management.py "
              "--ignore=$pkg/inference/tests/test_stability.py "
              "--ignore=$pkg/inference/tests/test_main.py "
              "--ignore=$pkg/inference/tests/test_proxy.py "
              "--deselect inference/tests/test_manager.py::test_manager_start_crash_quick_return "
              "--deselect inference/tests/test_manager.py::test_download_model_success "
              "--deselect inference/tests/test_manager.py::test_manager_start_model "
              "--deselect inference/tests/test_metrics.py::test_metrics_endpoint_returns_prometheus_format "
              "--deselect inference/tests/test_metrics.py::test_proxy_unavailable_increments_counter "
              "--deselect inference/tests/test_metrics.py::test_metrics_content_type_is_prometheus "
              "--deselect inference/tests/test_metrics.py::test_metrics_includes_memory_bytes_after_monitor_update "
              "--deselect inference/tests/test_model_name_case_normalization.py::test_inference_endpoints_normalize_model_name "
              "-v --tb=short -p no:cacheprovider",
              timeout=300
          )
    '';
  }
)
