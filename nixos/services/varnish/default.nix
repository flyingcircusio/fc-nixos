{ pkgs, lib, config, ... }: let
  cfg = config.flyingcircus.services.varnish;
  vcfg = config.services.varnish;

  inherit (lib) mkOption mkEnableOption types;

  sanitizeConfigName = name: builtins.replaceStrings ["."] ["-"] (lib.strings.sanitizeDerivationName name);
  mkVclName = file: "vcl_${builtins.head (lib.splitString "." (builtins.baseNameOf file))}";

  vhostConfigPath = hcfg: if (builtins.isPath hcfg.config) then hcfg.config else (pkgs.writeText "${hcfg.host}.vcl" hcfg.config);

  mkHostSelection = hcfg: let
    includefile = vhostConfigPath hcfg;
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
  mainActivationCommands = let
    name = mkVclName mainConfig;
  in ''
    vcl.load ${name} ${mainConfig}
    vcl.use ${name}
  '';

  commandsfile = pkgs.writeText "varnishd-commands" ''
    ${vhostActivationCommands}
    ${mainActivationCommands}
  '';
in {
  options.flyingcircus.services.varnish = {
    enable = mkEnableOption "varnish";
    extraCommandLine = mkOption {
      type = types.separatedString " ";
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
      enableConfigCheck = true;

      stateDir = "/run/varnishd";
      extraCommandLine = lib.concatStringsSep " " [ cfg.extraCommandLine "-I /etc/varnish/startup" ];
      inherit (cfg) http_address;
      config = ''
        vcl 4.0;
        import std;

        backend default {
          .host = "0.0.0.0";
          .port = "80";
        }

        sub vcl_recv {
          return (synth(503, "Varnish is starting up"));
        }
      '';
    };

    environment.etc."varnish/startup".source = commandsfile;

    systemd.services.varnish = {
      stopIfChanged = false;
      reloadTriggers = [ commandsfile ];
      reload = ''
        vadm="${vcfg.package}/bin/varnishadm -n ${vcfg.stateDir}"
        cat /etc/varnish/startup | $vadm

        coldvcls=$($vadm vcl.list | grep " cold " | ${pkgs.gawk}/bin/awk {'print $5'})

        if [ ! -z "$coldvcls" ]; then
          for vcl in "$coldvcls"; do
            $vadm vcl.discard $vcl
          done
        fi
      '';

      serviceConfig.RestartSec = lib.mkOverride 90 "10s";
    };

    system.checks = lib.mkIf vcfg.enableConfigCheck (map (vhost: (pkgs.runCommand "check-varnish-syntax-${vhost.host}" {} ''
        ${vcfg.package}/bin/varnishd -C -f ${vhostConfigPath vhost} 2> $out || (cat $out; exit 1)
      ''))
      (builtins.attrValues cfg.virtualHosts)
    );

  };
}
