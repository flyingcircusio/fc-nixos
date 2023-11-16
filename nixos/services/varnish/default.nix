{ pkgs, lib, config, ... }: let
  cfg = config.flyingcircus.services.varnish;
  inherit (lib) mkOption mkEnableOption types;

  sanitizeConfigName = name: builtins.replaceStrings ["."] ["-"] (lib.strings.sanitizeDerivationName name);
  mkVclName = file: "vcl_${builtins.head (lib.splitString "." (builtins.baseNameOf file))}";

  mkHostSelection = hcfg: let
    includefile = if (builtins.isPath hcfg.config) then hcfg.config else (pkgs.writeText "${hcfg.host}.vcl" hcfg.config);
    # Varnish uses a two-step approach with config names and labels, that we
    # leverage in this way:
    # 1. Every vhost received a config file that is written as a VCL config
    #    in the nix store, so every vhost's config file name changes when
    #    the config changes. We reflect this change in the config name within
    #    Varnish so that we can load multiple configs for the same vhost
    #    at the same time to facilitate graceful switchover.
    # 2. The label for every vhost stays the same, independent of any changes
    #    in the config. The label is then pointed to a new (versioned) name
    #    from step 1 to perform the switch-over.
    name = mkVclName includefile;
    label = "label-${sanitizeConfigName hcfg.host}";
  in {
    # This is the VCL snippet that will be embedded into the main VCL config.
    config = ''
      if (${hcfg.condition}) {
        return(vcl(${label}));
      }
    '';
    # These are the commands to activate new config (both at startup and reload.)
    command = ''
      vcl.load ${name} ${includefile}
      vcl.label ${label} ${name}
    '';
  };

  mainConfig = pkgs.writeText "main-config" ''
    vcl 4.0;
    import std;

    # An (invalid) backend that will never be used but is needed
    # to created a syntactically valid config.
    backend default {
      .host = "0.0.0.0";
      .port = "80";
    }

    sub vcl_recv {
      ${virtualHostSelection}

      return (synth(503, "Internal Error"));
    }
  '';

  vhosts = map mkHostSelection (builtins.attrValues cfg.virtualHosts);
  virtualHostSelection = lib.concatStringsSep "else" (map (x: x.config) vhosts);

  vhostActivationCommands = lib.concatStringsSep "\n" (map (x: x.command) vhosts);
  mainActivationCommands = ''
    vcl.load ${name} ${mkVclName mainConfig}
    vcl.use ${name}
  '';

  commandsfile = pkgs.writeText "varnishd-commands" ''
    ${vhostActivationCommands}
    ${mainActivationCommands}
    '';

  # Only activate the NixOS module config if there is no legacy config.
  commandsFileArg = lib.optionalString (cfg.config == null) "-I ${commandsfile})";
in {
  options.flyingcircus.services.varnish = {
    enable = mkEnableOption "varnish";
    config = mkOption {
      type = types.nullOr types.str;
    };
    extraCommandLine = mkOption {
      type = types.str;
      default = "";
    };
    http_address = mkOption {
      type = types.str;
      default = "*:8008";
    };
    virtualHosts = mkOption {
      type = types.attrsOf (types.submodule ({ name, config, ... }: {
        options = {
          host = mkOption {
            type = types.str;
            default = name;
          };

          config = mkOption {
            type = types.lines;
          };

          condition = mkOption {
            type = types.str;
            default = ''req.http.Host == "${config.host}"'';
          };
        };
      }));
      default = {};
    };
  };

  config = lib.mkIf cfg.enable {
    services.varnish = {
      enable = true;
      enableConfigCheck = false;
      extraCommandLine = lib.concatStringsSep [ cfg.extraCommandLine commandsFileArg ];
      inherit (cfg) http_address;
      config = if cfg.config == null then ''
        vcl 4.0;
        import std;

        backend default {
          .host = "0.0.0.0";
          .port = "80";
        }

        sub vcl_recv {
          return (synth(503, "Varnish is starting up"));
        }
      '' else cfg.config;
    };

    systemd.services.varnish = let
      vcfg = config.services.varnish;
    in {
      reloadIfChanged = true;
      restartTriggers = [ cfg.extraCommandLine vcfg.package cfg.http_address cfg.config ];
      reload = ''
        vadm="${vcfg.package}/bin/varnishadm -n ${vcfg.stateDir}"
        cat ${commandsfile} | $vadm

        coldvcls=$($vadm vcl.list | grep " cold " | ${pkgs.gawk}/bin/awk {'print $5'})

        if [ ! -z "$coldvcls" ]; then
          for vcl in "$coldvcls"; do
            $vadm vcl.discard $vcl
          done
        fi
      '';

      serviceConfig.RestartSec = lib.mkOverride 90 "10s";
    };
  };
}
