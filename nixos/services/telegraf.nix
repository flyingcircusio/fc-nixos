# telegraf adaptions.
# Note that there are both `services.telegraf` and
# `flyingcircus.services.telegraf` in use. The latter is the home for FC
# additions whilst the former referes to what upstream defines.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.telegraf;
  fclib = config.fclib;

  unifiedConfig = lib.recursiveUpdate
    cfg.extraConfig
    { inputs = config.flyingcircus.services.telegraf.inputs; };

  telegrafShowConfig = pkgs.writeScriptBin "telegraf-show-config" ''
    cat $(systemctl cat telegraf | grep "ExecStart=" | cut -d" " -f3 | tr -d '"')
    echo ""
    echo "# Config from config dir begins here"
    echo ""
    cat ${if builtins.pathExists /etc/local/telegraf then "${/etc/local/telegraf}/*.conf" else ""}
  '';

  # Partially copied from nixos/modules/services/monitoring/telegraf.nix.
  configFile = pkgs.runCommand "config.toml" {
    buildInputs = [ pkgs.remarshal ];
  } ''
    remarshal -if json -of toml \
      < ${pkgs.writeText "config.json" (builtins.toJSON unifiedConfig)} \
      > $out
  '';



in {
  options = {
    flyingcircus.services.telegraf = {

      inputs = mkOption {
        default = {};
        type = types.attrsOf (types.listOf types.attrs);
        description = ''
          Easy to use attrset of telegraf inputs. Will be folded into
          services.telegraf.extraConfig.
        '';
        example = {
          varnish = [{
            binary = "${pkgs.varnish}/bin/varnishstat";
            stats = [ "all" ];
          }];
        };
      };

    };
  };

  config = mkIf cfg.enable {

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
        ExecStart = mkOverride 90 (concatStringsSep " " (fclib.join [
          ["${cfg.package}/bin/telegraf -config \"${configFile}\""]
          (if builtins.pathExists /etc/local/telegraf then ["-config-directory ${/etc/local/telegraf}"] else [])
        ]));
        Nice = -10;
      };
    };

  };
}
