{ config, pkgs, lib, ... }:
let
  role = config.flyingcircus.roles.lamp;

in {
  options = {
    flyingcircus.roles.lamp.enable =
      lib.mkEnableOption "Flying Circus LAMP stack";
  };

  config = lib.mkIf role.enable (
    let
      apacheConfFile = /etc/local/lamp/apache.conf;
      phpiniConfFile = /etc/local/lamp/php.ini;

      phpOptions = ''
          extension=${pkgs.php73Packages.memcached}/lib/php/extensions/memcached.so
          extension=${pkgs.php73Packages.imagick}/lib/php/extensions/imagick.so
          extension=${pkgs.php73Packages.redis}/lib/php/extensions/redis.so

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

          ; 

        '' + (lib.optionalString
                (builtins.pathExists phpiniConfFile)
                (builtins.readFile phpiniConfFile));
    in {
      services.httpd.enable = true;
      services.httpd.adminAddr = "admin@flyingcircus.io";
      services.httpd.logPerVirtualHost = true;
      services.httpd.group = "service";
      services.httpd.user = "nobody";
      services.httpd.extraConfig = ''
Listen localhost:8001

<IfModule mpm_prefork_module>
    StartServers 5
    MinSpareServers 2
    MaxSpareServers 5
    MaxRequestWorkers 10
    MaxConnectionsPerChild 20
</IfModule>

<VirtualHost localhost:8001>
<Location "/server-status">
    SetHandler server-status
</Location>
</VirtualHost>

<VirtualHost *:8000>
    ServerName "${config.networking.hostName}"
    DocumentRoot "/etc/local/lamp/docroot"
    <Directory "/etc/local/lamp/docroot">
        AllowOverride all
        Require all granted
        Options FollowSymlinks
        DirectoryIndex index.html index.php
    </Directory>
</VirtualHost>
      '' + (lib.optionalString
        (builtins.pathExists apacheConfFile)
        (builtins.readFile apacheConfFile));
      services.httpd.phpOptions = phpOptions;

      services.httpd.extraModules = [ "rewrite" "version" "status" ];
      services.httpd.enablePHP = true;
      services.httpd.phpPackage = pkgs.php73;

      services.httpd.listen = [ { port = 8000;} ];

      flyingcircus.localConfigDirs.lamp = {
        dir = "/etc/local/lamp";
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
          # The daemon currently crashes when run with the tideways user.
          # We have a ticket with tideways, run with nobody until this is
          # fixed.
          User = "nobody";
          Type = "simple";
        };
      };

  });

}
