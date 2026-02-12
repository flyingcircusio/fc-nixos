{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.flyingcircus.roles.ai-api-gateway;
  fclib = config.fclib;
  enc = config.flyingcircus.enc;
  settingsFormat = pkgs.formats.toml { };
  baseConfigFile = settingsFormat.generate "skvaider-config.toml" cfg.settings;
in
{
  options.flyingcircus.roles.ai-api-gateway = {
    enable = lib.mkEnableOption "AI gateway (skvaider)";
    port = lib.mkOption {
      type = lib.types.port;
      default = 23211;
      description = "skvaider port";
    };
    hostname = lib.mkOption {
      type = lib.types.str;
      default = "ai.${enc.parameters.location}.fcio.net";
      defaultText = "ai.<location>.fcio.net";
      description = "hostname configured in nginx";
    };
    settings = lib.mkOption {
      description = "skvaider config";
      default = { };
      type = lib.types.submodule {
        freeformType = settingsFormat.type;
        options = {
          aramaki.url = lib.mkOption {
            default = "wss://directory.fcio.net/aramaki";
            internal = true;
          };
          aramaki.state_directory = lib.mkOption {
            default = "/var/lib/skvaider/aramaki";
            internal = true;
          };
          aramaki.secret_salt = lib.mkOption {
            default = "@secret_salt@";
            internal = true;
          };
          aramaki.principal = lib.mkOption {
            default = enc.name;
            internal = true;
          };
          backend = lib.mkOption {
            description = "Backends configured in skvaider";
            type = with lib.types; listOf (attrsOf str);
            internal = true;
            default = builtins.map (val: {
              type = "skvaider";
              url = "http://${val.address}:8000";
            }) (builtins.filter (s: s.service == "ai-model-server-server") config.flyingcircus.encServices);
          };
          openai.models = lib.mkOption {
            description = "model config";
            type = with lib.types; attrsOf anything;
            default = { };
          };
          logging.access_log_path = lib.mkOption {
            default = "/var/log/skvaider/access.log";
            type = lib.types.str;
            internal = true;
          };
          logging.log_level = lib.mkOption {
            type = lib.types.str;
            default = "INFO";
          };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.skvaider-config = {
      description = "skvaider config generation";
      wantedBy = [ "multi-user.target" ];
      reloadTriggers = [ baseConfigFile ];

      unitConfig.PropagatesReloadTo = [ "skvaider.service" ];
      serviceConfig =
        let
          configGeneratorScript = pkgs.writeShellScript "skvaider-config-generation" ''
            cat /etc/nixos/enc.json | ${lib.getExe pkgs.jq} -r '.parameters.secret_salt' > /run/skvaider-config/.secret_salt
            cp ${baseConfigFile} /var/lib/skvaider/config.toml
            ${lib.getExe pkgs.replace-secret} "@secret_salt@" "/run/skvaider-config/.secret_salt" /var/lib/skvaider/config.toml
            chown skvaider: /var/lib/skvaider/config.toml
          '';
        in
        {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
          User = "skvaider";

          ExecStart = "+" + configGeneratorScript;
          ExecReload = "+" + configGeneratorScript;
          RuntimeDirectory = "skvaider-config";
          StateDirectory = "skvaider";
          StateDirectoryMode = "0750";
        };

    };
    systemd.services.skvaider = {
      description = "AI gateway (skvaider)";
      wantedBy = [ "multi-user.target" ];
      bindsTo = [ "skvaider-config.service" ];
      after = [ "skvaider-config.service" ];
      # Currently, we only support one worker because we would otherwise have multiple aramaki connections with the same app ID
      script = ''
        ${lib.getExe' pkgs.fc.skvaider "gunicorn"} -b "127.0.0.1:${toString cfg.port}" "skvaider:app_factory()" -w 1 -k uvicorn_worker.UvicornWorker
      '';
      environment = {
        SKVAIDER_CONFIG_FILE = "/var/lib/skvaider/config.toml";
      };
      serviceConfig = {
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        UMask = "0022";
        User = "skvaider";
        Restart = "on-failure";
        StateDirectory = "skvaider";
        StateDirectoryMode = "0750";
        LogsDirectory = "skvaider";
        LogsDirectoryMode = "0750";
      };
    };
    users = {
      users.skvaider = {
        description = "Skvaider user";
        group = "service";
        isSystemUser = true;
      };
    };
    services.logrotate.settings.skvaider = {
      create = "0640 skvaider service";
      files = [ "/var/log/skvaider/*.log" ];
      frequency = "daily";
      su = "skvaider service";
      rotate = 7;
      copytruncate = true;
    };

    flyingcircus.services.nginx.enable = true;
    services.nginx.virtualHosts.${cfg.hostname} = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_read_timeout 1200s;
          proxy_buffering off;
        '';
      };
    };

    flyingcircus.services.telegraf.inputs.prometheus = [
      {
        urls = [ "http://127.0.0.1:${toString cfg.port}/metrics" ];
      }
    ];

    flyingcircus.services.sensu-client.checks = {
      skvaider = {
        notification = "Skvaider provides appropriate responses";
        interval = 300;
        timeout = 60;
        command = "${pkgs.fc.check-skvaider}/bin/check_skvaider https://${cfg.hostname} /etc/local/sensu-client/skvaider.key";
      };
    };

  };
}
