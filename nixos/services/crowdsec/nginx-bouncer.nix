{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.crowdsec-nginx-bouncer;
  format = pkgs.formats.keyValue { };

  cfg-crowdsec = config.services.crowdsec;
  runtime-dir-name = "crowdsec-nginx-bouncer";
  final-config-file = "/run/${runtime-dir-name}/config.yaml";
in
{
  options.services.crowdsec-nginx-bouncer =
    let
      inherit (lib)
        types
        mkOption
        mkEnableOption
        mkPackageOption
        ;
    in
    {
      enable = mkEnableOption "CrowdSec NGINX Bouncer";

      package = mkPackageOption pkgs "crowdsec-nginx-bouncer" { };

      registerBouncer = {
        enable = mkOption {
          type = types.bool;
          description = ''
            Whether to automatically register the bouncer to the locally running
            `crowdsec` service.

            When authenticating to an external CrowdSec API, you may use the
            [](#opt-services.crowdsec-nginx-bouncer.secrets.apiKeyPath) option
            instead.
          '';
          default = config.services.crowdsec.enable;
          defaultText = lib.literalExpression "config.services.crowdsec.enable";
        };
        bouncerName = mkOption {
          type = types.nonEmptyStr;
          description = "Name to register the bouncer as to the CrowdSec API";
          default = "crowdsec-nginx-bouncer";
        };
      };

      secrets = {
        apiKeyPath = mkOption {
          type = types.nullOr types.path;
          description = ''
            Path to the API key to authenticate with a local CrowdSec API.

            You need to call `cscli bouncers add <bouncer-name>` to register
            the bouncer and get this API key.

            When authenticating to the locally running `crowdsec` service, you may use the
            [](#opt-services.crowdsec-nginx-bouncer.registerBouncer.enable) option instead.
          '';
          default = null;
        };
      };

      settings = mkOption {
        description = ''
          Settings for the main CrowdSec NGINX Bouncer.

          Refer to the defaults at <https://github.com/crowdsecurity/lua-cs-bouncer/blob/main/config_example.conf>.
        '';
        default = { };
        type = types.submodule {
          freeformType = format.type;
          options = {
            API_URL = mkOption {
              type = types.str;
              description = "URL of the local API.";
              example = "http://127.0.0.1:8080";
              default = "http://${config.services.crowdsec.settings.config.api.server.listen_uri}";
              defaultText = lib.literalExpression ''http://$\{config.services.crowdsec.settings.config.api.server.listen_uri}'';
            };
            API_KEY = mkOption {
              type = types.nullOr types.str;
              description = ''
                API key to authenticate with a local CrowdSec API.

                You need to call `cscli bouncers add <bouncer-name>` to register
                the bouncer and get this API key.

                Setting this option will store this secret in the Nix store.
                Instead, you should set the `services.crowdsec-nginx-bouncer.secrets.apiKeyPath`
                option, which will read the value at runtime.
              '';
              default = null;
            };
            APPSEC_URL = mkOption {
              type = types.str;
              description = "URL of the AppSec component of CrowdSec.";
              example = "http://127.0.0.1:7422";
            };
            CAPTCHA_PROVIDER = mkOption {
              type = types.str;
              default = "";
            };
            MODE = mkOption {
              type = types.enum [
                "live"
                "stream"
              ];
              default = "stream";
              description = "Operating mode of CrowdSec NGINX bouncer.";
            };
          };
        };
      };
    };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          cfg.registerBouncer.enable || (cfg.secrets.apiKeyPath != null) || (cfg.settings.api_key != null);
        message = ''
          An API key must be set for the bouncer to be able to authenticate to a local crowdsec API.

          See the `registerBouncer.enable` and `secrets.apiKeyPath` options of
          `services.crowdsec-nginx-bouncer` for more information.
        '';
      }
      {
        assertion = !(cfg.registerBouncer.enable && (cfg.secrets.apiKeyPath != null));
        message = ''
          The `registerBouncer.enable` and `secrets.apiKeyPath` options of
          `services.crowdsec-nginx-bouncer` are mutually exclusive.
        '';
      }
      {
        assertion = !(cfg.registerBouncer.enable && !config.services.crowdsec.enable);
        message = ''
          The `services.crowdsec-nginx-bouncer.registerBouncer.enable` option
          requires the `crowdsec` service to be enabled.
        '';
      }
    ];

    # Use a placeholder for the api_key if it is to be read from a file at runtime
    services.crowdsec-nginx-bouncer.settings = {
      API_KEY =
        if (cfg.registerBouncer.enable || (cfg.secrets.apiKeyPath != null)) then "@API_KEY_FILE@" else null;
      BAN_TEMPLATE_PATH = "${pkgs.luaPackages.lua-cs-bouncer.templates}/ban.html";
      CAPTCHA_TEMPLATE_PATH = "${pkgs.luaPackages.lua-cs-bouncer.templates}/captcha.html";
    };

    services.nginx = {
      lua = {
        enable = true;
        extraPackages = ps: with ps; [ lua-cs-bouncer ];
      };
      appendHttpConfig = ''
        lua_shared_dict crowdsec_cache 50m;
        init_by_lua_block {
          cs = require "crowdsec"
          local ok, err = cs.init("${final-config-file}", "crowdsec-nginx-bouncer/v1.2.3")
          if ok == nil then
            ngx.log(ngx.ERR, "[Crowdsec] " .. err)
            error()
          end
          ngx.log(ngx.ALERT, "[Crowdsec] Initialisation done")
        }

        map $server_addr $unix {
          default 0;
          "~unix:" 1;
        }

        access_by_lua_block {
          local cs = require "crowdsec"
          if ngx.var.unix == "1" then
            ngx.log(ngx.DEBUG, "[Crowdsec] Unix socket request ignoring...")
          else
            cs.Allow(ngx.var.remote_addr)
          end
        }

        init_worker_by_lua_block {
          cs = require "crowdsec"
          local mode = cs.get_mode()
          if string.lower(mode) == "stream" then
            ngx.log(ngx.INFO, "Initializing stream mode for worker " .. tostring(ngx.worker.id()))
            cs.SetupStream()
          end

          if ngx.worker.id() == 0 then
            ngx.log(ngx.INFO, "Initializing metrics for worker " .. tostring(ngx.worker.id()))
            cs.SetupMetrics()
          end
        }
      '';
    };

    systemd = {
      tmpfiles.settings."10-crowdsec-nginx-bouncer" = {
        "/var/lib/crowdsec-nginx-bouncer-register".d = {
          user = cfg-crowdsec.user;
          group = cfg-crowdsec.user;
        };
      };

      services =
        let
          apiKeyFile = "/var/lib/crowdsec-nginx-bouncer-register/api-key.cred";
        in
        {
          crowdsec-nginx-bouncer-register = lib.mkIf cfg.registerBouncer.enable rec {
            description = "Register the CrowdSec NGINX Bouncer to the local CrowdSec service";
            wantedBy = [ "multi-user.target" ];
            after = [ "crowdsec.service" ];
            wants = after;
            path = [ config.services.crowdsec.package ];
            script = ''
              echo "Checking bouncer registration..."
              if cscli bouncers list --output json | ${lib.getExe pkgs.jq} -e -- ${lib.escapeShellArg "any(.[]; .name == \"${cfg.registerBouncer.bouncerName}\")"} >/dev/null; then
                echo "Bouncer already registered. Verify the API key is still present"
                if [ ! -f ${apiKeyFile} ]; then
                  echo "Bouncer registered but API key is not present"
                  echo "Unregistering bouncer..."
                  cscli bouncers delete ${cfg.registerBouncer.bouncerName} || true
                else
                  echo "API key file exists, nothing to do"
                  exit 0
                fi
              else
                echo "Bouncer not registered"
                echo "Remove any previously saved API key"
                rm -f '${apiKeyFile}'
              fi

              echo "Register the bouncer and save the new API key"
              if ! cscli bouncers add --output raw -- ${lib.escapeShellArg cfg.registerBouncer.bouncerName} > ${apiKeyFile} 2>&1; then
                echo "Failed to register the bouncer"
                cat ${apiKeyFile} || true  # Show error message
                rm -f ${apiKeyFile}
                exit 1
              fi

              chmod 0440 ${apiKeyFile} || true
              echo "Successfully registered bouncer and saved API key"

              cscli bouncers list
            '';
            serviceConfig = {
              Type = "oneshot";

              # Run as crowdsec user to be able to use cscli
              User = config.services.crowdsec.user;
              Group = config.services.crowdsec.group;

              ReadWritePaths = [
                "/var/lib/crowdsec"
                "/var/lib/crowdsec-nginx-bouncer-register"
              ];

              DynamicUser = true;
              LockPersonality = true;
              PrivateDevices = true;
              ProtectClock = true;
              ProtectControlGroups = true;
              ProtectHome = true;
              ProtectHostname = true;
              ProtectKernelLogs = true;
              ProtectKernelModules = true;
              ProtectKernelTunables = true;
              RestrictNamespaces = true;
              RestrictRealtime = true;
              SystemCallArchitectures = "native";

              RestrictAddressFamilies = "none";
              CapabilityBoundingSet = [ "" ];
              SystemCallFilter = [
                "@system-service"
                "~@privileged"
                "~@resources"
              ];
              UMask = "0077";
            };
          };

          crowdsec-nginx-bouncer-setup =
            let
              generateConfig = pkgs.writeShellScript "crowdsec-nginx-bouncer-config" ''
                set -euo pipefail
                umask 077

                # Copy the template to the final location
                cp ${format.generate "crowdsec-nginx-bouncer-config-template.conf" cfg.settings} ${final-config-file}
                chmod 0600 ${final-config-file}

                # Replace the api_key placeholder with the secret
                ${lib.getExe pkgs.replace-secret} '@API_KEY_FILE@' "$CREDENTIALS_DIRECTORY/API_KEY_FILE" ${final-config-file}
              '';

            in
            {
              before = [ "nginx.service" ];
              after = lib.optional cfg.registerBouncer.enable "crowdsec-nginx-bouncer-register.service";
              wantedBy = [ "multi-user.target" ];
              restartIfChanged = true;

              serviceConfig = {
                Type = "oneshot";
                ExecStart = [
                  generateConfig
                  "+/run/current-system/systemd/bin/systemctl start nginx-config-reload.service --no-block"
                ];
                # Load the api_key secret to be able to use it when generating the final config
                LoadCredential =
                  if (cfg.registerBouncer.enable) then
                    "API_KEY_FILE:${apiKeyFile}"
                  else if (cfg.secrets.apiKeyPath != null) then
                    "API_KEY_FILE:${cfg.secrets.apiKeyPath}"
                  else
                    null;

                User = "nginx";
                Group = "nginx";
                RuntimeDirectory = runtime-dir-name;
                RuntimeDirectoryPreserve = true;

                RestrictAddressFamilies = [
                  "AF_NETLINK"
                  "AF_UNIX"
                  "AF_INET"
                  "AF_INET6"
                ];
                UMask = "0077";
              };
            };
        };
    };
  };

  meta = {
    maintainers = with lib.maintainers; [
      leona
    ];
  };
}
