# telegraf adaptions.
# Note that there are both `services.telegraf` and
# `flyingcircus.services.telegraf` in use. The latter is the home for FC
# additions whilst the former referes to what upstream defines.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.telegraf;

  unifiedConfig = lib.recursiveUpdate
    cfg.extraConfig
    { inputs = config.flyingcircus.services.telegraf.inputs; };

  # Copied from nixos/modules/services/monitoring/telegraf.nix.
  # I don't know a better way to get the -config-directory option into ExecStart.
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

    environment.etc."local/telegraf/README.txt".text = ''
      There is a telegraf daemon running on this machine to gather statistics.
      To gather additional or custom statistis add a proper configuration file
      here. `*.conf` will beloaded.

      See https://github.com/influxdata/telegraf/blob/master/docs/CONFIGURATION.md
      for details on how to configure telegraf.
    '';

    systemd.tmpfiles.rules = [
      "d /etc/local/telegraf 2775 root service"
      "d /run/telegraf 0755 telegraf"
    ];

    systemd.services.telegraf = {
      serviceConfig = {
        ExecStart = mkOverride 90 ''
          ${cfg.package}/bin/telegraf -config "${configFile}" \
            -config-directory /etc/local/telegraf
        '';
        Nice = -10;
      };
    };

  };
}
