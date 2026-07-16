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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # Settings defaults at lib.mkDefault priority (1000) rather than the
        # option's default priority (1500). This ensures that when a caller
        # sets other keys in settings = { ... } (at priority 100), these
        # per-key defaults are not silently dropped by attrsOf's priority
        # resolution — they survive as long as the caller's definition
        # doesn't explicitly include the same key.
        flyingcircus.roles.ai-model-server.skvaider-inference.settings = lib.mkDefault {
          enable = true;
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
        hardware.nvidia-container-toolkit.enable = true;
        hardware.nvidia.nvidiaSettings = false;
        hardware.nvidia.open = true;
        services.xserver.videoDrivers = [ "nvidia" ];
        hardware.nvidia-container-toolkit.suppressNvidiaDriverAssertion = true;

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

        flyingcircus.services.sensu-client.checks.nvidia_gpu_reset_required = {
          notification = "NVIDIA GPU requires reset (GSP hang or bus fault)";
          # Exits 2 (critical) if any GPU has gpu_recovery_action=Reset.
          # This is the post-fault state: driver has given up and needs either
          # nvidia-smi --gpu-reset or a full reboot to recover.
          # nvidia-smi comes from hardware.nvidia (local config) via /run/current-system/sw.
          command = ''
            nvidia_smi=''${NVIDIA_SMI:-/run/current-system/sw/bin/nvidia-smi}
            output=$($nvidia_smi -q -x 2>&1)
            smi_status=$?
            if [ "$smi_status" -ne 0 ]; then
              echo "CRITICAL: nvidia-smi -q -x failed: $output"
              exit 2
            fi
            count=$(printf '%s\n' "$output" \
              | ${pkgs.gnugrep}/bin/grep -c '<gpu_recovery_action>Reset</gpu_recovery_action>' \
              || true)
            if [ "$count" -gt 0 ]; then
              echo "CRITICAL: $count GPU(s) require reset (run: nvidia-smi --gpu-reset -i <id>)"
              exit 2
            fi
            echo "OK: no GPUs require reset"
          '';
          interval = 60;
        };

        flyingcircus.services.sensu-client.checks.nvidia_gpu_smi_sane = {
          notification = "NVIDIA GPU nvidia-smi returning N/A or ERR! (possible GSP firmware hang)";
          # Query a set of fields that must always have real values on a healthy GPU.
          # N/A or ERR! on any of these indicates the driver has lost contact with
          # the GPU — the same state seen on ike01 after the Xid 119/154 GSP hang.
          # Fields deliberately chosen: all are non-optional on Blackwell under normal
          # operation regardless of power state (unlike e.g. memory_temp which is N/A
          # when the sensor is absent).
          command = ''
            nvidia_smi=''${NVIDIA_SMI:-/run/current-system/sw/bin/nvidia-smi}
            output=$($nvidia_smi \
              --query-gpu=index,gpu_uuid,power.draw,temperature.gpu,utilization.gpu \
              --format=csv,noheader 2>&1)
            smi_status=$?
            if [ "$smi_status" -ne 0 ]; then
              echo "CRITICAL: nvidia-smi query failed: $output"
              exit 2
            fi
            bad=$(printf '%s\n' "$output" \
              | ${pkgs.gawk}/bin/awk -F', ' '{
                  for (i=2; i<=NF; i++)
                    if ($i == "[N/A]" || $i == "N/A" || $i == "ERR!" || $i ~ /^\[[^]]*ERR[^]]*\]$/) {
                      print "GPU"$1": field "i" = "$i; found=1
                    }
                } END { exit 0 }')
            if [ -n "$bad" ]; then
              echo "CRITICAL: nvidia-smi fields N/A or ERR!: $bad"
              exit 2
            fi
            echo "OK: all GPU nvidia-smi fields sane"
          '';
          interval = 60;
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
          "d /var/log/skvaider 0750 skvaider service -"
          "d ${cfg.skvaider-inference.settings.models_dir} 0755 skvaider service -"
          "d /var/lib/skvaider/debug 0750 skvaider service -"
          "e /var/lib/skvaider/debug 4 -" # clean up debug logs older than 4 days
          "A /var/log/skvaider - - - - g:sudo-srv:r-x,g:admins:r-x"
          "a /var/log/skvaider - - - - d:g:sudo-srv:r,d:g:admins:r"
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
          { bin_path = "/run/current-system/sw/bin/nvidia-smi"; }
        ];
        services.logrotate.settings.skvaider-inference = {
          create = "0640 skvaider service";
          files = [
            "/var/log/skvaider/inference.log"
            "/var/log/skvaider/inference-*.log"
            "/var/log/skvaider/access.log"
          ];
          frequency = "daily";
          su = "skvaider service";
          rotate = 7;
          copytruncate = true;
        };

      }
    ]
  );
}
