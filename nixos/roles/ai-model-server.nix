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
                description = "Model name";
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

            hf_token = lib.mkOption {
              type = lib.types.str;
              description = "huggingface token";
            };

            settings = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = {
                models_dir = "/var/lib/skvaider/model";
                server = {
                  port = 8000;
                  host = "0.0.0.0";
                };
              };
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
        environment.systemPackages = [
          (pkgs.writeShellScriptBin "nvtop-nvidia" ''
            exec ${pkgs.nvtopPackages.nvidia}/bin/nvtop "$@"
          '')
          (pkgs.writeShellScriptBin "nvtop-full" ''
            exec ${pkgs.nvtopPackages.full}/bin/nvtop "$@"
          '')
          pkgs.nvtopPackages.full
        ];

        boot.kernelPackages = lib.mkForce (pkgs.linuxPackagesFor pkgs.linuxKernelGPU);

        boot.kernelModules = [ "nvidia" ];

        flyingcircus.roles.ai-model-server.skvaider-inference.settings.embedding_verification_file =
          lib.mkDefault ./embeddings-reference.json;

        flyingcircus.passwordlessSudoPackages = [
          # Allow applying config and restarting services to service users
          {
            commands = [
              "bin/systemctl start"
              "bin/systemctl stop"
            ];
            package = pkgs.systemd;
            users = [
              "skvaider"
            ];
          }
        ];

        systemd.services.skvaider-inference = lib.mkIf cfg.skvaider-inference.enable {
          description = "Skvaider inference service";
          wantedBy = [ "multi-user.target" ];
          environment = {
            HF_HUB_DISABLE_PROGRESS_BARS = "1";
            HF_TOKEN = cfg.skvaider-inference.hf_token;
            HOME = cfg.skvaider-inference.settings.models_dir;
          };
          script =
            let
              configfile =
                (pkgs.formats.toml { }).generate "skvaider_inference_settings.toml"
                  cfg.skvaider-inference.settings;
            in
            ''
              ${lib.getExe' pkgs.fc.skvaider "skvaider-inference"} -c ${configfile}
            '';
          path = [
            pkgs.llama-cpp-rocm
            pkgs.rocmPackages.rocm-smi
            "/run/current-system/sw" # for nvidia-x11 giving us nvidia-smi, which is used for GPU monitoring in Skvaider
          ];

          requires = [ "network-online.target" ];
          serviceConfig = {
            StateDirectory = "skvaider";
            User = "skvaider";
            Group = "service";
            StateDirectoryMode = "0755";
            CapabilityBoundingSet = [
              # sudo needs those:
              "CAP_SETUID"
              "CAP_SETGID"
              "CAP_DAC_READ_SEARCH"
              "CAP_SYS_RESOURCE"
            ];
            DeviceAllow = [
              # CUDA
              # https://docs.nvidia.com/dgx/pdf/dgx-os-5-user-guide.pdf
              # https://github.com/NixOS/nixpkgs/blob/fa56d7d6de78f5a7f997b0ea2bc6efd5868ad9e8/nixos/modules/services/misc/ollama.nix#L267C45-L267C70
              "char-nvidiactl"
              "char-nvidia-caps"
              "char-nvidia-frontend"
              "char-nvidia-uvm"
              # ROCm
              "char-drm"
              "char-fb"
              "char-kfd"
            ];
            PrivateDevices = false; # unhides acceleration devices
            SupplementaryGroups = [
              "render"
              # CUDA
              "video"
            ];
            Restart = "always";
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
          "d ${cfg.skvaider-inference.settings.models_dir} 0755 skvaider service -"
        ];

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
          (pkgs.writeShellScriptBin "nvtop-amd" ''
            exec ${pkgs.nvtopPackages.amd}/bin/nvtop "$@"
          '')
        ];

        systemd.services.rocm-runtime-config = {
          description = "Perform rocm runtime configuration";
          wantedBy = [ "multi-user.target" ];
          serviceConfig.Type = "oneshot";
          script = ''
            ${pkgs.rocmPackages.rocm-smi}/bin/rocm-smi --setprofile 4  # compute optimized
            ${pkgs.rocmPackages.rocm-smi}/bin/rocm-smi --showprofile   # record the updated settings in the log file
          '';
        };

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

      {
        flyingcircus.services.telegraf.inputs.prometheus = lib.mkIf cfg.skvaider-inference.enable [
          {
            urls = [
              "http://{cfg.skvaider-inference.settings.server.host}:${toString cfg.skvaider-inference.settings.server.port}/metrics"
            ];
          }
        ];
      }
    ]
  );
}
