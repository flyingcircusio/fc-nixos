{ pkgs, lib, config, ... }: let
  cfg = config.flyingcircus.services.varnish;
  inherit (lib) mkOption mkEnableOption types;

  sanitizeConfigName = name: builtins.replaceStrings ["."] ["-"] (lib.strings.sanitizeDerivationName name);
  mkVclName = file: "vcl_${builtins.head (lib.splitString "." (builtins.baseNameOf file))}";

  mkHostSelection = hcfg: let
    includefile = if (builtins.isPath hcfg.config) then hcfg.config else (pkgs.writeText "${hcfg.host}.vcl" hcfg.config);
    # vcl_hash-${hcfg.host} -> has to change with the file's contents
    name = mkVclName includefile;
    # has to stay the same when only the file's the content changes, such that a reload only "moves" the label over to the new config
    label = "label-${sanitizeConfigName hcfg.host}";
  in {
    config = ''
      if (${hcfg.condition}) {
        return(vcl(${label}));
      }
    '';
    command = ''
      vcl.load ${name} ${includefile}
      vcl.label ${label} ${name}
    '';
  };

  mainConfig = pkgs.writeText "main-config" ''
    vcl 4.0;
    import std;

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
  commandsfile = pkgs.writeText "varnishd-commands" (lib.concatStringsSep "\n" ((map (x: x.command) vhosts) ++ (let
    name = mkVclName mainConfig;
  in [''
    vcl.load ${name} ${mainConfig}
    vcl.use ${name}
  ''])));

  extraCommandLine = cfg.extraCommandLine + (lib.optionalString (cfg.extraCommandLine != "") " ") + lib.optionalString (cfg.config == null) "-I ${commandsfile}";
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
      inherit extraCommandLine;
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
