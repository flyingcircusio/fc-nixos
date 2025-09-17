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
  baseConfigFile = settingsFormat.generate "skvaider-config.toml" {
    aramaki = {
      url = cfg.aramakiUrl;
      state_directory = "/var/lib/skvaider/aramaki";
      secret_salt = "@secret_salt@";
      principal = enc.name;
    };
    backend = builtins.map (val: {
      type = "openai";
      url = "http://${val.address}:11434";
    }) (builtins.filter (s: s.service == "ai-model-server-server") config.flyingcircus.encServices);
    openai.models = {
      "gpt-oss:20b" = {
        num_ctx = 131072;
      };
      "gpt-oss:120b" = {
        num_ctx = 131072;
      };
      "mistral-small3.2:latest" = {
        num_ctx = 65536;
      };
    };
    logging = {
      access_log_path = "/var/log/skvaider/access.log";
      log_level = cfg.logLevel;
    };
  };
in
{
  options.flyingcircus.roles.ai-api-gateway = {
    enable = lib.mkEnableOption "AI gateway (skvaider)";
    aramakiUrl = lib.mkOption {
      type = lib.types.str;
      default = "wss://directory.fcio.net/aramaki";
      internal = true;
    };
    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "INFO";
      description = "skvaider log level";
    };
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
  };
}
