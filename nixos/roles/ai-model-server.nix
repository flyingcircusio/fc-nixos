{
  config,
  lib,
  pkgs,
  ...
}:

with builtins;

let
  fclib = config.fclib;
  cfg = config.flyingcircus.roles.ai-model-server;
  scfg = config.services.ollama;

  checkOllamaCpuOffload = pkgs.writeShellApplication {
    name = "check_ollama_cpu_offload";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      url="http://${scfg.host}:${toString scfg.port}/api/ps"

      if ! response=$(curl -s --fail "$url"); then
        echo "CRITICAL: Failed to connect to Ollama at $url"
        exit 2
      fi

      # Check for models loaded into CPU
      # We look for models where size > size_vram
      # We output the names of such models

      offloaded_models=$(echo "$response" | jq -r '.models[] | select(.size > .size_vram) | "\(.name) (size: \(.size), vram: \(.size_vram))"')

      if [ -n "$offloaded_models" ]; then
        echo "WARNING: Some models are partially or fully loaded into CPU:"
        echo "$offloaded_models"
        exit 1
      else
        echo "OK: All models are fully loaded into GPU"
        exit 0
      fi
    '';
  };

in
{
  options = {
    flyingcircus.roles.ai-model-server = {
      enable = lib.mkEnableOption "Enable GPU server role with AI inference capabilities";
      supportsContainers = fclib.mkDisableDevhostSupport;

      # Enabled by default, can be disabled for running in VMs or
      # tests.
      enableRocm = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable ROCM for AMD GPU acceleration";
      };

      # Model configuration
      models = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether to enable this model";
              };

              name = lib.mkOption {
                type = lib.types.str;
                description = "Model name for ollama";
              };
            };
          }
        );
        default = {
          gpt-oss-20b = {
            name = "gpt-oss:20b";
          };
          gpt-oss-120b = {
            name = "gpt-oss:120b";
          };
          mistral-small = {
            name = "mistral-small3.2:latest";
          };
          bge-m3 = {
            name = "bge-m3:567m";
          };
          embeddinggemma = {
            name = "embeddinggemma:300m";
          };
          nomic-embed-text = {
            name = "Nomic-embed-text:v1.5";
          };
        };
        description = "Predefined models to make available";
      };

      skvaider-inference = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "Enable Skvaider inference service";

            port = lib.mkOption {
              type = lib.types.int;
              default = 8000;
              description = "Port for Skvaider inference service";
            };

            modelPath = lib.mkOption {
              type = lib.types.str;
              default = "/var/lib/skvaider/model";
              description = "Path to the Skvaider model directory";
            };

            settings = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
              description = "Additional Skvaider inference settings";
            };
          };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # Fixed shared config for CPU and AMD
      {
        environment.variables.OLLAMA_HOST = "${scfg.host}:${toString scfg.port}";

        services.ollama = {
          enable = true;
          host = fclib.mkPlatform config.networking.hostName;
          environmentVariables = {
            OLLAMA_DEBUG = "1";
            OLLAMA_NUM_PARALLEL = "10";
            OLLAMA_FLASH_ATTENTION = "1";
            OLLAMA_SCHED_SPREAD = "0";
            OLLAMA_MULTIUSER_CACHE = "1";
            OLLAMA_NEW_ENGINE = "1";
            OLLAMA_NEW_ESTIMATES = "1";
            OLLAMA_KEEP_ALIVE = "-1"; # infinite, expire if needed
          };
          loadModels =
            let
              enabledModels = lib.filterAttrs (n: v: v.enable) cfg.models;
            in
            lib.mapAttrsToList (n: v: v.name) enabledModels;
        };

        systemd.services.skvaider-inference = lib.mkIf cfg.skvaider-inference.enable {
          description = "Skvaider inference service";
          wantedBy = [ "multi-user.target" ];
          environment = {
            PORT = toString cfg.skvaider-inference.port;
            MODELS_DIR = "${cfg.skvaider-inference.modelPath}";
            SKVAIDER_CONFIG_FILE =
              (pkgs.formats.toml { }).generate "skvaider_inference_settings.toml"
                cfg.skvaider-inference.settings;
          };
          serviceConfig = {
            ExecStart = "${pkgs.fc.skvaider}/bin/inference";
            StateDirectory = "skvaider";
            User = "skvaider";
            Group = "service";
            StateDirectoryMode = "0755";
            CapabilityBoundingSet = [ "" ];
            DeviceAllow = [
              # ROCm
              "char-drm"
              "char-fb"
              "char-kfd"
            ];
            PrivateDevices = false; # unhides acceleration devices
            SupplementaryGroups = [
              "render"
            ];
          };
        };
        users = {
          users.skvaider = {
            description = "Skvaider user";
            group = "service";
            isSystemUser = true;
          };
        };
        systemd.tmpfiles.rules = [
          "d /var/lib/skvaider 0755 skvaider service -"
          "d /var/lib/skvaider/model 0755 skvaider service -"
          "d ${cfg.skvaider-inference.modelPath} 0755 skvaider service -"
        ];

        systemd.services.ollama.serviceConfig.Restart = "always";

        flyingcircus.services.sensu-client.checks = {
          ollama_health = {
            notification = "Ollama service health check";
            command = "check_http -H ${scfg.host} -p ${toString scfg.port} -u /api/tags";
            interval = 300;
          };

          ollama_cpu_offload = {
            notification = "Ollama CPU offload check";
            command = "${checkOllamaCpuOffload}/bin/check_ollama_cpu_offload";
            interval = 300;
          };
        };
      }

      # ROCM specific config
      (lib.mkIf cfg.enableRocm {
        # Allow unfree packages for GPU drivers and AI models
        nixpkgs.config = {
          allowUnfree = true;
          rocmSupport = true;
        };

        # GPU hardware and driver configuration
        hardware.graphics = {
          enable = true;
          enable32Bit = true;
        };
        services.xserver.videoDrivers = [ "amdgpu" ];

        # Environment packages for AMD ROCM
        environment.systemPackages = [
          pkgs.rocmPackages.rocminfo
          pkgs.rocmPackages.rocm-smi
          pkgs.nvtopPackages.amd
        ];

        systemd.tmpfiles.rules =
          let
            rocmEnv = pkgs.symlinkJoin {
              name = "rocm-combined";
              paths = with pkgs.rocmPackages; [
                rocblas
                hipblas
                clr
              ];
            };
          in
          [
            "L+  /opt/rocm  - - - -  ${rocmEnv}"
          ];

        # AMD specific ollama setup
        services.ollama = {
          package = pkgs.ollama-rocm;
          acceleration = "rocm";
          # Pin to gfx1100 LLVM target for Radeon PRO W7900 GPUs
          rocmOverrideGfx = "11.0.0";
        };

        services.telegraf.extraConfig.inputs.amd_rocm_smi = [
          {
            # Exclude the GPU uuid to avoid excess label cardinality
            taginclude = [
              "name"
            ];
            # see https://docs.influxdata.com/telegraf/v1/input-plugins/amd_rocm_smi/ for fields
          }
        ];
        services.telegraf.extraConfig.agent.always_include_global_tags = true;
        systemd.services.telegraf.path = [ pkgs.rocmPackages.rocm-smi ];
      })
    ]
  );
}
