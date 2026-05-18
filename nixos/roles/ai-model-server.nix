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
              default = { };
              description = "Additional Skvaider inference settings";
            };
          };
        };
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          # Settings defaults at lib.mkDefault priority (1000) rather than the
          # option's default priority (1500). This ensures that when a caller
          # sets other keys in settings = { ... } (at priority 100), these
          # per-key defaults are not silently dropped by attrsOf's priority
          # resolution — they survive as long as the caller's definition
          # doesn't explicitly include the same key.
          flyingcircus.roles.ai-model-server.skvaider-inference.settings = lib.mkDefault {
            models_dir = "/var/lib/skvaider/model";
            server.port = 8000;
            server.host = "0.0.0.0";
            embedding_verification_file = lib.mkDefault ./embeddings-reference.json;
          };

          # NVIDIA driver, CUDA toolkit, cuDNN and nvtopPackages.nvidia pull
          # unfree packages. Keep the allow-list in pkgs/overlay.nix so the
          # unstable CUDA package set and the NixOS role use the same names.
          flyingcircus.allowedUnfreePackageNames = pkgs.nvidiaUnfreePackageNames;

          nixpkgs.config.cudaSupport = true;
          hardware.graphics.enable = true;
          hardware.nvidia.open = true;
          hardware.nvidia.nvidiaSettings = false;
          services.xserver.videoDrivers = [ "nvidia" ];
          hardware.nvidia-container-toolkit.enable = true;

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
                    # log_dir is module-owned (ties to tmpfiles + logrotate);
                    # inject after user settings so it is never clobbered by a
                    # partial logging = { ... } override in /etc/local/nixos/.
                    (
                      lib.recursiveUpdate cfg.skvaider-inference.settings {
                        logging.log_dir = "/var/log/skvaider";
                      }
                    );
              in
              ''
                ${lib.getExe' pkgs.fc.skvaider "skvaider-inference"} -c ${configfile}
              '';
            path = [
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
            "d /var/log/skvaider 0755 skvaider service -"
            "d ${cfg.skvaider-inference.settings.models_dir} 0755 skvaider service -"
            # Clean up debug/access logs older than 4 days
            "e /var/lib/skvaider 4 -"
          ];

        }

        {
          flyingcircus.services.telegraf.inputs.prometheus = lib.mkIf cfg.skvaider-inference.enable [
            {
              urls = [
                "http://${cfg.skvaider-inference.settings.server.host}:${toString cfg.skvaider-inference.settings.server.port}/metrics"
              ];
            }
          ];
          flyingcircus.services.telegraf.inputs.nvidia_smi = lib.mkIf cfg.skvaider-inference.enable [
            { }
          ];
          services.logrotate.settings.skvaider-inference = {
            create = "0640 skvaider service";
            files = [
              "/var/log/skvaider/inference.log"
              "/var/log/skvaider/inference-*.log"
            ];
            frequency = "daily";
            su = "skvaider service";
            rotate = 7;
            copytruncate = true;
          };

        }
      ]
    ))
    {
      systemd.tmpfiles.rules = lib.mkIf cfg.skvaider-inference.enable [
        "d /var/lib/skvaider 0755 skvaider service -"
        "d /var/log/skvaider 0755 skvaider service -"
        "d ${cfg.skvaider-inference.settings.models_dir} 0755 skvaider service -"
        "e /var/lib/skvaider 4 -" # clean up debug logs older than 4 days
      ];
    }
  ];
}
