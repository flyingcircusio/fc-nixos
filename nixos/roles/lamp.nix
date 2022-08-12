{ config, options, pkgs, lib, ... }:
let
  role = config.flyingcircus.roles.lamp;
  fclib = config.fclib;
in {

  options = with lib; {
    flyingcircus.roles.lamp = {
      enable = mkEnableOption "Flying Circus LAMP stack";
      supportsContainers = fclib.mkEnableContainerSupport;

      useFPM = fclib.mkObsoleteOption "FPM is always used now.";

      fpmMaxChildren = mkOption {
        type = types.int;
        default = 25;
      };

      apache_conf = mkOption {
        type = types.lines;
        default = "";
      };

      php_ini = mkOption {
        type = types.lines;
        default = "";
      };

      php = mkOption {
        type = types.package;
        default = pkgs.lamp_php80;
        description = ''
          The package to use.
        '';
      };

      tideways_api_key = mkOption {
        type = types.str;
        default = "";
      };

      vhosts = mkOption {
        type = with types; listOf (submodule {
          options = {
            port = mkOption { type = int; };
            docroot = mkOption { type = str; };
            apacheExtraConfig = mkOption {
              type = lines;
              default = "";
              description = ''
                Additional text appended to virtualhost section of apache config.
              '';
            };
            pool = mkOption {
              type = lib.types.attrsOf lib.types.anything;
              description = "Overrides for underlying NixOS Pool options";
              default = {};
            };
          };
        });
        default = [];
      };

    };
  };

  config = let

      phpOptions = ''
          ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
          ; General settings

          output_buffering = On
          short_open_tag = On
          curl.cainfo = /etc/ssl/certs/ca-certificates.crt
          sendmail_path = /run/wrappers/bin/sendmail -t -i

          ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
          ; opcache
          opcache.enable = 1
          opcache.enable_cli = 0
          opcache.interned_strings_buffer = 8
          opcache.max_accelerated_files = 40000
          opcache.memory_consumption = 512
          opcache.validate_timestamps = 0

          ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
          ; logging and errors

          error_log = syslog
          display_errors = Off
          log_errors = On

          ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
          ; memory and execution limits

          memory_limit = 1024m
          max_execution_time = 800

          ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
          ; session management

          session.auto_start = Off

          ; Custom PHP ini
          ${role.php_ini}
        '' + pkgs.lib.optionalString (role.tideways_api_key != "") ''
          ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
          ; Tideways
          ;
          ; This is intended to be production-ready so it doesn't create too
          ; much overhead. If you need to increase tracing, then you can
          ; adjust this in your local php.ini

          extension=${pkgs.tideways_module}/lib/php/extensions/tideways-php-${phpMajorMinor}-zts.so

          tideways.connection = tcp://127.0.0.1:9135

          tideways.features.phpinfo = 1

          tideways.dynamic_tracepoints.enable_web = 1
          tideways.dynamic_tracepoints.enable_cli = 1

          ; customers need to add their api key locally
          tideways.api_key = ${role.tideways_api_key}
        '';
        phpMajorMinor = lib.concatStringsSep "." (lib.take 2 (builtins.splitVersion role.php.version));
        phpMajor = builtins.head (builtins.splitVersion role.php.version);
    in

      lib.mkMerge [
      {
        warnings =
          fclib.obsoleteOptionWarning
            options
            [ "flyingcircus" "roles" "lamp" "useFPM" ]
            "FPM is always used now.";
      }

      # General config if the role is enabled but not specific to the
      # selection of mod_php or FPM
      (lib.mkIf role.enable {
        services.httpd.enable = true;
        services.httpd.adminAddr = "admin@flyingcircus.io";
        services.httpd.mpm = "event";

        # We always provide the PHP cli environment but we need to ensure
        # to choose the right one in case someone uses the LAMP role.
        environment.systemPackages = [
          role.php
          role.php.packages.composer
        ];

        # Provide a similar PHP config for the PHP CLI as for Apache (httpd).
        # The file referenced by PHPRC is loaded together with the php.ini
        # from the global PHP package which only specifies the extensions.
        environment.variables.PHPRC = "${pkgs.writeText "php.ini" phpOptions}";
        services.httpd.logPerVirtualHost = true;
        services.httpd.group = "service";
        services.httpd.user = "nobody";
        services.httpd.extraModules = [ "rewrite" "version" "status" "proxy_fcgi" ];
        services.httpd.extraConfig = ''
          # Those options are chosen for prefork
          # StartServers 2 (default)
          # MinSpareServers 5 (default)
          # MaxSpareServers 10 (Default)

          # MaxRequestWorkers default: 256, limit to lower number
          # to avoid starvation/thrashing
          MaxRequestWorkers 150

          # Determine lifetime of processes
          # MaxConnectionsPerChild default: 0, set limit to
          # avoid potential memory leaks
          MaxConnectionsPerChild     10000

          Listen localhost:7999
          <VirtualHost localhost:7999>
          <Location "/server-status">
              SetHandler server-status
          </Location>
          </VirtualHost>

          # reuse _must_ be disable or apache will confuse different
          # FPM pools and also screw up with keepalives consuming backend
          # connections.
          <Proxy "fcgi://localhost/" enablereuse=off>
          </Proxy>

          '' +
          # * vhost configs
          (lib.concatMapStrings (vhost:
            let port=toString vhost.port;
            in
            ''

            Listen *:${port}
            <VirtualHost *:${port}>
                ServerName "${config.networking.hostName}"
                DocumentRoot "${vhost.docroot}"
                <Directory "${vhost.docroot}">
                    AllowOverride all
                    Require all granted
                    Options FollowSymlinks
                    DirectoryIndex index.html index.php
                </Directory>
                <FilesMatch "\.php$">
                    SetHandler "proxy:unix:${config.services.phpfpm.pools."lamp-${port}".socket}|fcgi://localhost/"
                </FilesMatch>
                ${vhost.apacheExtraConfig}
            </VirtualHost>
            ''
          ) role.vhosts) +
          role.apache_conf;

        # The upstream module has a default that makes Apache listen on port 80
        # which conflicts with our webgateway role.
        services.httpd.virtualHosts = {};

        services.phpfpm.phpPackage = role.php;

        services.phpfpm.pools = builtins.listToAttrs (map
          (vhost: {
             name = "lamp-${toString vhost.port}";
             value = lib.attrsets.recursiveUpdate {
                user = config.services.httpd.user;
                group = config.services.httpd.group;
                phpOptions = phpOptions;
                settings = {
                  "listen.owner" = config.services.httpd.user;
                  "listen.group" = config.services.httpd.group;
                  "pm" = "dynamic";
                  "pm.max_children" = (toString role.fpmMaxChildren);
                  "pm.start_servers" = "5";
                  "pm.min_spare_servers" = "5";
                  "pm.max_spare_servers" = "10";
                };
              } vhost.pool; # only contains override values
          }) role.vhosts);

        flyingcircus.services.sensu-client.checks = {
          httpd_status = {
            notification = "Apache status page";
            command = "check_http -H localhost -p 7999 -u /server-status?auto -v";
            timeout = 30;
          };
        };

        flyingcircus.services.telegraf.inputs = {
          apache  = [{
            urls = [ "http://localhost:7999/server-status?auto" ];
          }];
        };

        systemd.tmpfiles.rules = [
          "d /var/log/httpd 0750 root service"
          "a+ /var/log/httpd - - - - group:sudo-srv:r-x"
        ];

      })

      (lib.mkIf (role.tideways_api_key != "") {

        # tideways daemon
        users.groups.tideways.gid = config.ids.gids.tideways;

        users.users.tideways = {
          description = "tideways daemon user";
          uid = config.ids.uids.tideways;
          isSystemUser = true;
          group = "tideways";
          extraGroups = [ "service" ];
        };

        systemd.services.tideways-daemon = rec {
          description = "tideways daemon";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network.target" ];
          after = wants;
          serviceConfig = {
            ExecStart = ''
              ${pkgs.tideways_daemon}/tideways-daemon --address=127.0.0.1:9135
            '';
            Restart = "always";
            RestartSec = "60s";
            User = "tideways";
            Type = "simple";
          };
        };
      })
      ];
}
