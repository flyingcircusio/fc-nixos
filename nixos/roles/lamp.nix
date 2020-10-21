{ config, pkgs, lib, ... }:
let
  role = config.flyingcircus.roles.lamp;
  localDir = "/etc/local/lamp";
  apacheConfFile = localDir + "/apache.conf";
  phpiniConfFile = localDir + "/php.ini";

in {
  options = with lib; {
    flyingcircus.roles.lamp = {
      enable = mkEnableOption "Flying Circus LAMP stack";

      apache_conf = mkOption {
        type = types.lines;
        default = (lib.optionalString
          (builtins.pathExists apacheConfFile)
          (builtins.readFile apacheConfFile));
      };

      php_ini = mkOption {
        type = types.lines;
        default = (lib.optionalString
                (builtins.pathExists phpiniConfFile)
                (builtins.readFile phpiniConfFile));
      };

      vhosts = mkOption {
        type = with types; listOf (submodule {
          options = {
            port = mkOption { type = int; };
            docroot = mkOption { type = str; };
          };
        });
        default = [];
      };

      # BBB deprecated
      simple_docroot = mkOption {
          type = types.bool;
          default = (builtins.pathExists (localDir + "/docroot"));
      };
    };
  };

  config = lib.mkIf role.enable (
    let

      phpOptions = ''
          extension=${pkgs.php73Extensions.memcached}/lib/php/extensions/memcached.so
          extension=${pkgs.php73Extensions.imagick}/lib/php/extensions/imagick.so
          extension=${pkgs.php73Extensions.redis}/lib/php/extensions/redis.so

          ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
          ; General settings

          output_buffering = On
          short_open_tag = On
          curl.cainfo = /etc/ssl/certs/ca-certificates.crt
          sendmail_path = /run/wrappers/bin/sendmail -t -i

          ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
          ; Tideways
          ;
          ; This is intended to be production-ready so it doesn't create too 
          ; much overhead. If you need to increase tracing, then you can 
          ; adjust this in your local php.ini

          extension=${pkgs.tideways_module}/lib/php/extensions/tideways-php-7.3-zts.so

          tideways.connection = tcp://127.0.0.1:9135

          tideways.features.phpinfo = 1

          tideways.dynamic_tracepoints.enable_web = 1
          tideways.dynamic_tracepoints.enable_cli = 1

          ; customers need to add their api key locally
          ; tideways.api_key = xxxxx

          ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
          ; opcache

          zend_extension = opcache.so
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
        '';
    in {

      services.httpd.enable = true;
      services.httpd.adminAddr = "admin@flyingcircus.io";
      services.httpd.logPerVirtualHost = true;
      services.httpd.group = "service";
      services.httpd.user = "nobody";
      services.httpd.extraConfig = ''
        <IfModule mpm_prefork_module>
            StartServers 5
            MinSpareServers 2
            MaxSpareServers 5
            MaxRequestWorkers 25
            MaxConnectionsPerChild 20
        </IfModule>

        Listen localhost:7999
        <VirtualHost localhost:7999>
        <Location "/server-status">
            SetHandler server-status
        </Location>
        </VirtualHost>
        '' +
        # Original simple one-host-one-port-one-docroot setup
        # BBB This can be phased out at some point.
        (lib.optionalString
          role.simple_docroot
          ''

          Listen *:8000
          <VirtualHost *:8000>
              ServerName "${config.networking.hostName}"
              DocumentRoot "${localDir}/docroot"
              <Directory "${localDir}/docroot">
                  AllowOverride all
                  Require all granted
                  Options FollowSymlinks
                  DirectoryIndex index.html index.php
              </Directory>
          </VirtualHost>
          '') +
        # * vhost configs
        (lib.concatMapStrings (vhost:
          ''

          Listen *:${toString vhost.port}
          <VirtualHost *:${toString vhost.port}>
              ServerName "${config.networking.hostName}"
              DocumentRoot "${vhost.docroot}"
              <Directory "${vhost.docroot}">
                  AllowOverride all
                  Require all granted
                  Options FollowSymlinks
                  DirectoryIndex index.html index.php
              </Directory>
          </VirtualHost>
          ''
        ) role.vhosts) +
        role.apache_conf;

      services.httpd.phpOptions = phpOptions;

      services.httpd.extraModules = [ "rewrite" "version" "status" ];
      services.httpd.enablePHP = true;
      services.httpd.phpPackage = pkgs.php73;

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

      services.logrotate.extraConfig = ''
        /var/log/httpd/*.log {
          create 0644 root root
          postrotate
            systemctl reload httpd
          endscript
        }
      '';

      flyingcircus.localConfigDirs.lamp = {
        dir = localDir;
        user = "nobody";
      };

      # tideways daemon
      users.groups.tideways.gid = config.ids.gids.tideways;

      users.users.tideways = {
        description = "tideways daemon user";
        uid = config.ids.uids.tideways;
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

  });

}
