{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.varnish;
  fccfg = config.flyingcircus.roles.webproxy;
  fclib = config.fclib;

  varnishCfg = fclib.configFromFile /etc/local/varnish/default.vcl vcl_example;

  vcl_example = ''
    vcl 4.0;
    backend test {
      .host = "127.0.0.1";
      .port = "8080";
    }
  '';

  cacheMemory = (fclib.currentMemory 256) / 100 * fccfg.mallocMemoryPercentage;

  configFile = pkgs.writeText "default.vcl" cfg.config;

  varnishadm = "${cfg.package}/bin/varnishadm";

in
{

  options = {

    flyingcircus.roles.webproxy = {
      enable = mkEnableOption "Flying Circus varnish server role";

      mallocMemoryPercentage = mkOption {
        type = types.int;
        default = 50;
        description = "Percentage of system memory to allocate to malloc cache";
      };

    };
  };

  config = mkMerge [
    (mkIf fccfg.enable {

      environment.etc = {
        "local/varnish/README.txt".text = ''
          Varnish is enabled on this machine.

          Varnish is listening on: ${cfg.http_address}

          Put your configuration into `default.vcl`.
        '';
        "local/varnish/default.vcl.example".text = vcl_example;
        "current-config/varnish.vcl".source = configFile;
      };

      security.sudo.extraRules = [
        {
          commands = [ varnishadm ];
          groups = [ "sensuclient" ];
        }
      ];

      flyingcircus.services.sensu-client.checks = {
        varnish_status = {
          notification = "varnishadm status reports errors";
          command = "/run/wrappers/bin/sudo ${varnishadm} status";
          timeout = 60;
        };
        varnish_http = {
          notification = "varnish port 8008 HTTP response";
          command = "check_http -H localhost -p 8008 -c 10 -w 3 -t 20 -f ok";
        };
      };

      flyingcircus.services.telegraf.inputs = {
        varnish = [{
          binary = "${cfg.package}/bin/varnishstat";
          stats = ["all"];
        }];
      };

      services.varnish = {
        enable = true;
        http_address =
          lib.concatMapStringsSep " -a "
            (addr: "${addr}:8008")
            ((fclib.listenAddressesQuotedV6 "ethsrv") ++
             (fclib.listenAddressesQuotedV6 "lo"));
        config = varnishCfg;
        extraCommandLine = "-s malloc,${toString cacheMemory}M";
      };

      system.activationScripts.varnish-local = stringAfter [] ''
        install -d -o varnish -g service -m 02775 /etc/local/varnish
      '';

      systemd.services.varnish = {
        stopIfChanged = false;
        serviceConfig = {
          RestartSec = mkOverride 90 "10s";
        };
      };

    })

    {
      flyingcircus.roles.statshost.prometheusMetricRelabel = [
        {
          source_labels = [ "__name__" ];
          regex = "(varnish_client_req|varnish_fetch)_(.+)";
          replacement = "\${2}";
          target_label = "status";
        }
        {
          source_labels = [ "__name__" ];
          regex = "(varnish_client_req|varnish_fetch)_(.+)";
          replacement = "\${1}";
          target_label = "__name__";
        }

        # Relabel
        {
          source_labels = [ "__name__" ];
          regex = "varnish_(\\w+)_(.+)__(\\d+)__(.+)";
          replacement = "\${1}";
          target_label = "backend";
        }
        {
          source_labels = [ "__name__" ];
          regex = "varnish_(\1\w+)_(.+)__(\\d+)__(.+)";
          replacement = "varnish_\${4}";
          target_label = "__name__";
        }
      ];

      flyingcircus.roles.statshost.globalAllowedMetrics = [ "varnish" ];
    }

  ];
}
