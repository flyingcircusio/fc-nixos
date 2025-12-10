# telegraf adaptions.
# Note that there are both `services.telegraf` and
# `flyingcircus.services.telegraf` in use. The latter is the home for FC
# additions whilst the former referes to what upstream defines.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  upstreamCfg = config.services.telegraf;
  cfg = config.flyingcircus.services.telegraf;
  fclib = config.fclib;

  telegrafShowConfig = pkgs.writeScriptBin "telegraf-show-config" ''
    cat $(systemctl cat telegraf | grep "ExecStart=" | cut -d" " -f3 | tr -d '"')
    echo ""
    echo "# Config from config dir begins here"
    echo ""
    cat ${if builtins.pathExists /etc/local/telegraf then "${/etc/local/telegraf}/*.conf" else ""}
  '';

  settingsFormat = pkgs.formats.toml { };
  configFile = settingsFormat.generate "config.toml" upstreamCfg.extraConfig;

in
{

  imports = [
    ./psi_input.nix
  ];

  options = {
    flyingcircus.services.telegraf = {

      inputs = mkOption {
        default = { };
        type = types.attrsOf (types.listOf types.attrs);
        description = ''
          Easy to use attrset of telegraf inputs. Will be folded into
          services.telegraf.extraConfig.
        '';
        example = {
          varnish = [
            {
              binary = "${pkgs.varnish}/bin/varnishstat";
              stats = [ "all" ];
            }
          ];
        };
      };
      prometheus-metric_version = mkOption {
        default = 1;
        type = types.int;
        description = ''
          `metric_version` used by prometheus input and output plugin. Needs to
          be the same version for both plugins.
          See https://github.com/influxdata/telegraf/blob/master/plugins/inputs/prometheus/README.md#metric-format-configuration
        '';
      };
      environmentVariablesFromFile = mkOption {
        default = { };
        type = types.attrsOf types.str;
        description = ''
          Sets environment variables based on the content of given files.
          These will be interpolated into the config file using envsubst
          with this syntax: `$ENVIRONMENT` or `''${VARIABLE}`.
        '';
        example = {
          REDIS_PASSWORD = "/etc/local/redis/password";
        };
      };
    };
  };

  config = mkMerge [
    (mkIf upstreamCfg.enable {

      # merge in our platform configs…
      # …except for prometheus inputs, which get some further pre-processing further down this file
      services.telegraf.extraConfig.inputs =
        lib.removeAttrs config.flyingcircus.services.telegraf.inputs
          [ "prometheus" ];

      environment.systemPackages = [
        telegrafShowConfig
      ];

      environment.etc."local/telegraf/README.txt".text = ''
        There is a telegraf daemon running on this machine to gather statistics.
        To gather additional or custom statistics add a proper configuration file
        here. `*.conf` will be loaded.

        See https://github.com/influxdata/telegraf/blob/master/docs/CONFIGURATION.md
        for details on how to configure telegraf.
      '';

      systemd.tmpfiles.rules = [
        "d /etc/local/telegraf 2775 root service"
        "d /run/telegraf 0755 telegraf"
      ];

      systemd.services.telegraf = {
        serviceConfig = {
          LoadCredential = lib.mapAttrsToList (
            name: file: "${name}:${file}"
          ) cfg.environmentVariablesFromFile;
          ExecStartPre =
            let
              envInvocation = builtins.concatStringsSep "\n" (
                lib.mapAttrsToList (
                  name: file: "export ${name}=$(<$CREDENTIALS_DIRECTORY/${name})"
                ) cfg.environmentVariablesFromFile
              );
            in
            [
              (pkgs.writeShellScript "telegraf-pre-start" ''
                ${envInvocation}
                umask 077
                ${pkgs.envsubst}/bin/envsubst -i "${configFile}" > /var/run/telegraf/config.toml
              '')
            ];
          ExecStart = mkOverride 90 (
            concatStringsSep " " (
              lib.flatten [
                [ "${upstreamCfg.package}/bin/telegraf -config '/var/run/telegraf/config.toml'" ]
                (
                  if builtins.pathExists /etc/local/telegraf then
                    [ "-config-directory ${/etc/local/telegraf}" ]
                  else
                    [ ]
                )
              ]
            )
          );
          Nice = -10;
        };
      };

    })
    (mkIf (cfg.inputs ? prometheus) {
      # only set when that plugin is configured to be used, to not accidentally enable it without use
      services.telegraf.extraConfig.inputs.prometheus = builtins.map (
        attr:
        attr
        // {
          metric_version = cfg.prometheus-metric_version;
        }
      ) cfg.inputs.prometheus;
    })
  ];
}
