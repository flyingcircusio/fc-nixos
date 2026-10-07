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
  checkSkvaiderCmdSudoers = "${pkgs.fc.skvaider}/bin/check-skvaider https\\://${cfg.hostname} --config /var/lib/skvaider/config.toml";
  checkSkvaiderCmd = "${pkgs.fc.skvaider}/bin/check-skvaider https://${cfg.hostname} --config /var/lib/skvaider/config.toml";
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
          server.host = lib.mkOption {
            default = "127.0.0.1";
            type = lib.types.str;
            description = "IP to bind the server on";
          };
          server.port = lib.mkOption {
            default = cfg.port;
            type = lib.types.int;
            description = "Port to bind the server on";
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
          auth.admin_tokens = lib.mkOption {
            description = "List of static bearer tokens accepted by the proxy.";
            type = with lib.types; listOf str;
            default = [ ];
          };
          models = lib.mkOption {
            description = "model config";
            type = with lib.types; listOf anything;
            default = [ ];
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
        ${lib.getExe' pkgs.fc.skvaider "skvaider-proxy"} -c /var/lib/skvaider/config.toml
      '';
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
    systemd.tmpfiles.rules = [
      "d /var/lib/skvaider 0750 skvaider service - -"
      "d /var/lib/skvaider/debug 0750 skvaider service 4d -"

      "d /var/log/skvaider 0750 skvaider service - -"
      "A /var/log/skvaider - - - - g:sudo-srv:r-x,g:admins:r-x"
      "a /var/log/skvaider - - - - d:g:sudo-srv:r,d:g:admins:r"
    ];
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

    flyingcircus.passwordlessSudoRules = [
      {
        commands = [ checkSkvaiderCmdSudoers ];
        groups = [ "sensuclient" ];
        runAs = "skvaider";
      }
    ];

    flyingcircus.services.sensu-client.checks = {
      skvaider = {
        notification = "Skvaider provides appropriate responses";
        interval = 300;
        timeout = 60;
        command = "sudo -u skvaider ${checkSkvaiderCmd}";
      };
    };

  };
}
