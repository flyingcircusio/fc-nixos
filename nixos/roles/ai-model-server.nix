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
                description = "Model name for ollama";
              };

              description = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Model description";
              };

              license = lib.mkOption {
                type = lib.types.str;
                default = "unknown";
                description = "Model license information";
              };
            };
          }
        );
        default = {
          gpt-oss-20b = {
            name = "gpt-oss:20b";
            description = "GPT OSS 20B parameter model";
            license = "Apache 2.0";
          };
          gpt-oss-120b = {
            name = "gpt-oss:120b";
            description = "GPT OSS 120B parameter model";
            license = "Apache 2.0";
          };
          mistral-small = {
            name = "mistral-small3.2:latest";
            description = "Mistral Small 3.2 - good for OCR tasks";
            license = "Apache 2.0";
          };
        };
        description = "Predefined models to make available";
      };

      # Network configuration
      hostAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1"; # srv, see fclib
        description = "Host address for ollama to bind to";
      };

      # Storage configuration
      modelsPath = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/ollama/models";
        description = "Path to store ollama models";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Allow unfree packages for GPU drivers and AI models
    nixpkgs.config = {
      #   allowUnfree = true;
      #   rocmSupport = true;
    };

    # GPU hardware configuration
    # hardware.graphics = {
    #   enable = true;
    #   enable32Bit = true;
    # };

    # GPU drivers and kernel parameters
    # services.xserver.videoDrivers = [ "amdgpu" ];

    # boot.kernelParams = [ "pci=realloc" "pci=assign-busses" ];

    # Environment packages based on GPU type
    environment.systemPackages = [
      # AMD ROCm packages
      pkgs.rocmPackages.rocminfo
      pkgs.rocmPackages.rocm-smi
      pkgs.nvtopPackages.amd
    ];

    environment.variables.OLLAMA_HOST = "${cfg.hostAddress}:${toString scfg.port}";

    # Ollama service configuration
    services.ollama = {
      enable = true;
      acceleration = "rocm";
      models = cfg.modelsPath;
      host = cfg.hostAddress;
    };

    # Model pre-loading service (optional)
    systemd.services.ollama-model-preload = {
      description = "Pre-load configured AI models";
      wantedBy = [ "multi-user.target" ];
      after = [ "ollama.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "root";
      };
      script =
        let
          enabledModels = lib.filterAttrs (n: v: v.enable) cfg.models;
          preloadCommands = lib.mapAttrsToList (
            name: model:
            "${pkgs.curl}/bin/curl -X POST http://${cfg.hostAddress}:${toString scfg.port}/api/pull -d '{\"name\": \"${model.name}\"}'"
          ) enabledModels;
        in
        lib.concatStringsSep "\n" (
          [
            "echo 'Pre-loading AI models...'"
            "sleep 10" # Wait for ollama to be ready
          ]
          ++ preloadCommands
          ++ [
            "echo 'Model pre-loading completed'"
          ]
        );
    };

    # Health check service
    flyingcircus.services.sensu-client.checks = {
      ollama_health = {
        notification = "Ollama service health check";
        command = "${pkgs.curl}/bin/curl -f http://${cfg.hostAddress}:${toString scfg.port}/api/tags || exit 2";
        interval = 300;
      };
    };
  };
}
