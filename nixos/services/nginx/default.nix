{ lib, config, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.services.nginx;
  fclib = config.fclib;
  stateDir = config.services.nginx.stateDir;
  package = config.services.nginx.package;
  currentConf = "/etc/current-config/nginx.conf";

  vhostsJSON = fclib.jsonFromFile "/etc/local/nginx/vhosts.json" "{}";
  virtualHosts = lib.mapAttrs (
    _: val:
    (lib.optionalAttrs
      ((val ? addSSL || val ? onlySSL || val ? forceSSL) && val ? acmeEmail)
      { enableACME = true; }) // removeAttrs val [ "acmeEmail" ])
    vhostsJSON;

  acmeEmails =
    lib.mapAttrs (name: val: { email = val.acmeEmail; })
    (lib.filterAttrs (_: val: val ? acmeEmail ) vhostsJSON);

  localConfig =
    lib.optionalString (pathExists "/etc/local/nginx") "${/etc/local/nginx}";

  baseConfig = ''
    worker_processes ${toString (fclib.current_cores config 1)};
    worker_rlimit_nofile 8192;
  '';

  baseHttpConfig = ''
    # === Defaults ===
    default_type application/octet-stream;
    charset UTF-8;

    # === Logging ===
    map $remote_addr $remote_addr_anon_head {
      default 0.0.0;
      "~(?P<ip>\d+\.\d+\.\d+)\.\d+" $ip;
      "~(?P<ip>[^:]+:[^:]+:[^:]+):" $ip;
    }
    map $remote_addr $remote_addr_anon_tail {
      default .0;
      "~(?P<ip>\d+\.\d+\.\d+)\.\d+" .0;
      "~(?P<ip>[^:]+:[^:]+:[^:]+):" ::;
    }
    map $remote_addr_anon_head$remote_addr_anon_tail $remote_addr_anon {
        default 0.0.0.0;
        "~(?P<ip>.*)" $ip;
    }

    # same as 'anonymized'
    log_format main
        '$remote_addr_anon - $remote_user [$time_local] '
        '"$request" $status $bytes_sent '
        '"$http_referer" "$http_user_agent" '
        '"$gzip_ratio"';
    log_format anonymized
        '$remote_addr_anon - $remote_user [$time_local] '
        '"$request" $status $body_bytes_sent '
        '"$http_referer" "$http_user_agent" '
        '"$gzip_ratio"';
    log_format nonanonymized
        '$remote_addr - $remote_user [$time_local] '
        '"$request" $status $bytes_sent '
        '"$http_referer" "$http_user_agent" '
        '"$gzip_ratio"';
    log_format performance
        '$time_iso8601 $pid.$connection.$connection_requests '
        '$request_method "$scheme://$host$request_uri" $status '
        '$bytes_sent $request_length $pipe $request_time '
        '"$upstream_response_time" $gzip_ratio';

    open_log_file_cache max=64;
    access_log /var/log/nginx/access.log anonymized;
    access_log /var/log/nginx/performance.log performance;

    # === Buffers and timeouts ===
    client_body_timeout 10m;
    client_header_buffer_size 4k;
    client_header_timeout 10m;
    connection_pool_size 256;
    large_client_header_buffers 4 16k;
    request_pool_size 4k;
    send_timeout 10m;
    server_names_hash_bucket_size ${toString cfg.mapHashBucketSize};

    # === User-provided config ===
    include /etc/local/nginx/*.conf;
  '';

in
{
  options.flyingcircus.services.nginx = with lib; {
    enable = mkEnableOption "FC-customized nginx";

    httpConfig = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Configuration lines to be appended inside of the http {} block.
      '';
    };

    mapHashBucketSize = mkOption {
      type = types.int;
      default = 64;
      description = "Bucket size for the 'map' variables hash tables.";
    };

  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {

      environment.etc = {
        "local/nginx/README.txt".source = ./README.txt;

        "local/nginx/fastcgi_params" = {
          source = "${package}/conf/fastcgi_params";
        };

        "local/nginx/uwsgi_params" = {
          source = "${package}/conf/uwsgi_params";
        };

        "local/nginx/example-configuration".text =
          import ./example-config.nix { inherit config lib; };

        "local/nginx/modsecurity/README.txt".text = ''
          Here are example configuration files for ModSecurity.

          You need to adapt them to your needs *and* provide a ruleset. A common
          ruleset is the OWASP ModSecurity Core Rule Set (CRS) (https://www.modsecurity.org/crs/).
          You can get it via:

            git clone https://github.com/SpiderLabs/owasp-modsecurity-crs.git

          Save the adapted ruleset in a subdirectory here and adjust
          modsecurity_includes.conf.
        '';

        "local/nginx/modsecurity/modsecurity.conf.example".source =
          ./modsecurity.conf;

        "local/nginx/modsecurity/modsecurity_includes.conf.example".source =
          ./modsecurity_includes.conf;

        "local/nginx/modsecurity/unicode.mapping".source =
          "${pkgs.modsecurity_standalone.nginx}/unicode.mapping";
      };

      flyingcircus.services.telegraf.inputs = {
        nginx = [ {
          urls = [ "http://localhost/nginx_status" ];
        } ];
      };

      flyingcircus.services.sensu-client.checks = {
        nginx_status = {
          notification = "nginx does not listen on port 80";
          command =
            "check_http -H localhost -u /nginx_status -s server -c 5 -w 2";
          interval = 60;
        };
      } //
      (lib.mapAttrs' (name: _: (lib.nameValuePair "nginx_cert_${name}" {
        notification = "HTTPS cert for ${name} (Let's encrypt)";
        command = "check_http -H ${name} -p 443 -S -C 5";
        interval = 600;
      })) acmeEmails);

      networking.firewall.allowedTCPPorts = [ 80 443 ];

      security.acme.certs = acmeEmails;

      services.nginx = {
        enable = true;
        appendConfig = "";
        appendHttpConfig = baseHttpConfig + "\n" + cfg.httpConfig;
        eventsConfig = ''
          worker_connections 4096;
          multi_accept on;
        '';
        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;
        statusPage = true;
        inherit virtualHosts;
      };

      services.logrotate.config = ''
        /var/log/nginx/*access*log
        /var/log/nginx/*error*log
        /var/log/nginx/performance.log
        {
            rotate 92
            create 0644 nginx service
            postrotate
                systemctl kill nginx -s USR1 --kill-who=main
            endscript
        }
      '';

      systemd.tmpfiles.rules = [
        "d /var/log/nginx 0755 nginx"
        "d /etc/local/nginx 2775 nginx service"
        "d /etc/local/nginx/modsecurity 2775 nginx service"
      ];

      system.activationScripts.nginx-reload = lib.stringAfter [ "etc" ] ''
        if [[ ! -e ${stateDir}/reload.conf ]]; then
          install -D /dev/null ${stateDir}/reload.conf
        fi
        # reload not possible when structured vhosts have changed -> skip
        if [[ -n "$(find /etc/local/nginx -name '*.json' \
                    -newer ${stateDir}/reload.conf)" ]]; then
          echo -n "${localConfig}" > ${stateDir}/reload.conf
        # check if local config has changed
        elif [[ "$(< ${stateDir}/reload.conf )" != "${localConfig}" ]]; then
          echo "nginx: config change detected, reloading"
          if ${package}/bin/nginx -t -c ${currentConf} -p ${stateDir}; then
            ${pkgs.systemd}/bin/systemctl reload nginx.service || true
            echo -n "${localConfig}" > ${stateDir}/reload.conf
          else
            echo "nginx: not reloading due to error"
            false
          fi
        fi
      '';
    })

    {
      flyingcircus.roles.statshost.globalAllowedMetrics = [ "nginx" ];
    }
  ];
}
