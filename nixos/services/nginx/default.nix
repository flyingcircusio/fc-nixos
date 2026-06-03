# Note that Nginx is reloaded when config, unit file or package change.
# Future changes may require a full Nginx restart to become active.
# We can use systemd.services.nginx.restartTriggers to force a restart.
# This may also affect other services that use reloading.
{
  lib,
  config,
  pkgs,
  ...
}:

with builtins;
with lib;

let
  nixpkgs = (import ../../../release/versions.nix { }).nixpkgs;
  cfg = config.flyingcircus.services.nginx;
  nginxCfg = config.services.nginx;
  fclib = config.fclib;

  checkCert = "${pkgs.fc.check-tls-cert}/bin/check_tls_cert";

  lokiServer = fclib.findOneService "loki-collector";

  nginxShowConfig = pkgs.writeScriptBin "nginx-show-config" ''
    cat /etc/nginx/nginx.conf
  '';

  nginxCheckConfig = pkgs.writeScriptBin "nginx-check-config" ''
    #!${pkgs.runtimeShell}
    echo "Running built-in Nginx config validation (must pass in order to activate a config)..."
    ${lib.getExe nginxCfg.package} -c /etc/nginx/nginx.conf -g "user nginx;" -t || exit 2
    echo "Running gixy security checker (just informational)..."
    ${pkgs.gixy}/bin/gixy /etc/nginx/nginx.conf || exit 1
  '';

  nginxCheckWorkerAge = pkgs.writeScript "nginx-check-worker-age" ''
    config_age=$(expr $(date +%s) - $(stat --format=%Y /etc/nginx/nginx.conf) )
    main_pid=$(systemctl show nginx | grep -e '^MainPID=' | cut -d= -f 2)

    for pid in $(pgrep -P $main_pid); do
        worker_age=$(ps -o etimes= $pid)
        agediff=$(expr $worker_age - $config_age)

        # We want to ignore workers that are already shutting down after a reload request.
        # They don't accept new connections and should get killed after worker_shutdown_timeout expires.
        shutting_down=$(ps --no-headers $pid | grep 'shutting down')

        if [[ $agediff -gt 1 && -z $shutting_down ]]; then
            start_time=$(ps -o lstart= $pid)
            echo "Worker process $pid is $agediff seconds older than the config file (started $start_time)"

            if (( $agediff > 300 )); then
              workers_too_old_crit=1
            else
              workers_too_old_warn=1
            fi
        fi
    done

    if [[ $workers_too_old_crit ]]; then
        exit 2
    elif [[ $workers_too_old_warn ]]; then
        exit 1
    else
        echo "worker age OK"
    fi
  '';

  package = config.services.nginx.package;
  localCfgDir = config.flyingcircus.localConfigPath + "/nginx";

  vhostsWithTLS = lib.filterAttrs (
    _: vhost: vhost.onlySSL || vhost.addSSL || vhost.forceSSL
  ) nginxCfg.virtualHosts;

  nonAcmeVhostsWithTLS = lib.filterAttrs (
    _: vhost: (!vhost.enableACME && vhost.useACMEHost == null)
  ) vhostsWithTLS;

  mainConfig = ''
    worker_processes ${toString cfg.workerProcesses};
    worker_rlimit_nofile 8192;
    worker_shutdown_timeout ${toString cfg.workerShutdownTimeout};
  '';

  # Temp dirs that are expected by Nginx under /var/cache/nginx.
  # We manage them with tmpfiles ourselves to make sure permissions
  # are correct in all cases.
  tempSubdirs = [
    "proxy"
    "client_body"
    "fastcgi"
    "scgi"
    "uwsgi"
  ];

  baseHttpConfig = ''
    # === Defaults ===
    charset UTF-8;

    # === Logging ===

    # same as 'anaonymized'
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

    ${optionalString (!builtins.isNull lokiServer) ''
      log_format json_analytics escape=json '{'
        '"msec": "$msec", ' # request unixtime in seconds with a milliseconds resolution
        '"connection": "$connection", ' # connection serial number
        '"connection_requests": "$connection_requests", ' # number of requests made in connection
        '"pid": "$pid", ' # process pid
        '"request_id": "$request_id", ' # the unique request id
        '"request_length": "$request_length", ' # request length (including headers and body)
        '"remote_addr": "$remote_addr_anon", ' # client IP
        '"remote_user": "$remote_user", ' # client HTTP username
        '"remote_port": "$remote_port", ' # client port
        '"time_local": "$time_local", '
        '"time_iso8601": "$time_iso8601", ' # local time in the ISO 8601 standard format
        '"request": "$request", ' # full path no arguments if the request
        '"request_uri": "$request_uri", ' # full path and arguments if the request
        '"args": "$args", ' # args
        '"status": "$status", ' # response status code
        '"body_bytes_sent": "$body_bytes_sent", ' # the number of body bytes exclude headers sent to a client
        '"bytes_sent": "$bytes_sent", ' # the number of bytes sent to a client
        '"http_referer": "$http_referer", ' # HTTP referer
        '"http_user_agent": "$http_user_agent", ' # user agent
        '"http_x_forwarded_for": "$http_x_forwarded_for", ' # http_x_forwarded_for
        '"http_host": "$http_host", ' # the request Host: header
        '"server_name": "$server_name", ' # the name of the vhost serving the request
        '"request_time": "$request_time", ' # request processing time in seconds with msec resolution
        '"upstream": "$upstream_addr", ' # upstream backend server for proxied requests
        '"upstream_connect_time": "$upstream_connect_time", ' # upstream handshake time incl. TLS
        '"upstream_header_time": "$upstream_header_time", ' # time spent receiving upstream headers
        '"upstream_response_time": "$upstream_response_time", ' # time spent receiving upstream body
        '"upstream_response_length": "$upstream_response_length", ' # upstream response length
        '"upstream_cache_status": "$upstream_cache_status", ' # cache HIT/MISS where applicable
        '"ssl_protocol": "$ssl_protocol", ' # TLS protocol
        '"ssl_cipher": "$ssl_cipher", ' # TLS cipher
        '"scheme": "$scheme", ' # http or https
        '"request_method": "$request_method", ' # request method
        '"server_protocol": "$server_protocol", ' # request protocol, like HTTP/1.1 or HTTP/2.0
        '"pipe": "$pipe", ' # "p" if request was pipelined, "." otherwise
        '"gzip_ratio": "$gzip_ratio"'
      '}';

      access_log syslog:server=127.0.0.1:51893 json_analytics;

      ## Proxy defaults: buffer, but only to RAM.
      proxy_buffering                 on;
      proxy_request_buffering         on;
      proxy_max_temp_file_size        0;
    ''}

    # === Buffers and timeouts ===
    client_body_timeout 10m;
    client_header_buffer_size 4k;
    client_header_timeout 10m;
    connection_pool_size 256;
    large_client_header_buffers 4 16k;
    request_pool_size 4k;
    send_timeout 10m;

    ${optionalString (cfg.rateLimit.enable) ''
      # === Rate limiting ===

      # CVE-2023-44487 handling with relatively high limits to
      # not impact customer applications too much. Can be limited further
      # if necessary.
      limit_conn_zone $binary_remote_addr zone=addr:10m;
      limit_conn addr ${toString cfg.rateLimit.maxConcurrent};
      limit_conn_status 429;

      limit_req_zone $binary_remote_addr zone=perclient:10m rate=${toString cfg.rateLimit.maxRequestsPerSecond}r/s;
      limit_req zone=perclient burst=${toString cfg.rateLimit.burst};
      limit_req_status 429;
    ''}

    # === Temp Dirs ===
    # By default, Nginx creates another two levels of directories under the
    # temp dirs which doesn't make sense on a XFS filesystem.
    # By setting the options explicitly here we avoid that.
    ${lib.concatMapStringsSep "\n" (d: "${d}_temp_path /var/cache/nginx/${d};") tempSubdirs}
  '';

  plainConfigFiles = filter (p: lib.hasSuffix ".conf" p) (fclib.files localCfgDir);
  localHttpConfig = concatStringsSep "\n" (map readFile plainConfigFiles);
in
{
  imports = [
    (mkRemovedOptionModule [
      "flyingcircus"
      "services"
      "nginx"
      "disableDHEATMitigation"
    ] "The DHEAT mitigiation is now part of services.nginx.recommendedTlsSettings")
  ];

  options.flyingcircus.services.nginx = with lib; {
    enable = mkEnableOption "FC-customized nginx";

    defaultListenAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = fclib.network.fe.dualstack.addressesQuoted;
      defaultText = "addresses of the `fe` network (IPv4 & IPv6)";
      description = ''
        Addresses to listen on if a vhost does not specify any.
      '';
    };

    httpConfig = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Configuration lines to be appended inside of the http {} block.
      '';
    };

    workerShutdownTimeout = mkOption {
      type = types.int;
      default = 240;
      description = ''
        Configures a timeout (seconds) for a graceful shutdown of worker processes.
        When the time expires, nginx will try to close all the connections currently
        open to facilitate shutdown.
        By default, nginx will try to close connections 4 minutes after a reload.
      '';
    };

    workerProcesses = mkOption {
      type = types.int;
      description = ''
        Configures the number of worker processes.
      '';
      default = fclib.min [
        (fclib.currentCores 1)
        12
      ];
      defaultText = literalExpression "fclib.min [(fclib.currentCores 1) 12]";
    };

    rotateLogs = mkOption {
      type = types.int;
      default = 7;
      description = ''
        Configures how often log files are rotated before being removed.
        If count is 0, old versions are removed rather than rotated.
      '';
    };

    logPerVirtualHost = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Configures a separate access and error log in the `/var/log/nginx` directory for each virtualHost.
      '';
    };

    virtualHosts = mkOption {
      type = types.attrsOf (
        types.submodule (
          import "${nixpkgs}/nixos/modules/services/web-servers/nginx/vhost-options.nix" {
            inherit config lib;
          }
        )
      );
      default = { };
      visible = false;
      description = "Declarative vhost config";
    };

    rateLimit = {
      enable = mkEnableOption "Global rate limiting";

      maxConcurrent = mkOption {
        type = types.ints.positive;
        default = 200;
        description = ''
          Sets the maximum number of concurrent requests per client.
        '';
      };

      maxRequestsPerSecond = mkOption {
        type = types.ints.positive;
        default = 50;
        description = ''
          Sets the maximum number of requests per second per client.
        '';
      };

      burst = mkOption {
        type = types.ints.positive;
        default = 500;
        description = ''
          Sets the maximum number of requests to delay/queue if exceeding the rate limit.
        '';
      };
    };
  };

  # Inject our custom access/error logging to every vHosts' extraConfig
  options.services.nginx.virtualHosts = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        let
          servername = if config.serverName != null then config.serverName else name;
        in
        {
          options = {
            extraConfig = lib.mkOption {
              apply =
                orig:
                orig
                + lib.optionalString (cfg.logPerVirtualHost) ''
                  access_log /var/log/nginx/access-${servername}.log;
                  error_log /var/log/nginx/error-${servername}.log;
                '';
            };
          };
        }
      )
    );
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.etc = {
          "local/nginx/README.txt".source = ./README.txt;

          "local/nginx/fastcgi_params" = {
            source = "${package}/conf/fastcgi_params";
          };

          "local/nginx/uwsgi_params" = {
            source = "${package}/conf/uwsgi_params";
          };

          # file has moved; link back to the old location for compatibility reasons
          "local/nginx/htpasswd_fcio_users" = {
            source = "/etc/local/htpasswd_fcio_users.login";
          };

          "local/nginx/example-configuration".text = import ./example-plain-config.nix {
            inherit config lib;
          };

          "local/nginx/modsecurity/README.txt".text = ''
            Here are example configuration files for ModSecurity.

            You need to adapt them to your needs *and* provide a ruleset. A common
            ruleset is the OWASP ModSecurity Core Rule Set (CRS) (https://www.modsecurity.org/crs/).
            You can get it via:

              git clone https://github.com/SpiderLabs/owasp-modsecurity-crs.git

            Save the adapted ruleset in a subdirectory here and adjust
            modsecurity_includes.conf.
          '';

          "local/nginx/modsecurity/modsecurity.conf.example".source = ./modsecurity.conf;

          "local/nginx/modsecurity/modsecurity_includes.conf.example".source = ./modsecurity_includes.conf;

          "local/nginx/modsecurity/unicode.mapping".source = "${pkgs.libmodsecurity.src}/unicode.mapping";

          "local/nixos/nginx.nix.example".source = ./example-nixos-module.nix;
        };

        flyingcircus.services.telegraf.inputs = {
          nginx = [
            {
              urls = [ "http://localhost:81/nginx_status" ];
            }
          ];
        };

        flyingcircus.services.sensu-client.checks = {
          nginx_config = {
            notification = "Nginx configuration check problems";
            command = "/run/wrappers/bin/sudo ${lib.getExe nginxCheckConfig}";
            interval = 300;
          };

          nginx_status = {
            notification = "nginx does not listen on port 80";
            command = ''
              ${pkgs.monitoring-plugins}/bin/check_http \
                -H localhost -u /nginx_status -p 81 -s server -c 5 -w 2
            '';
            interval = 60;
          };

          nginx_worker_age = {
            notification = "Some nginx worker processes don't use the current config";
            command = "${nginxCheckWorkerAge}";
            interval = 60;
          };
        }
        // (lib.foldl' (
          acc: n:
          let
            vhost = vhostsWithTLS.${n};
            host = if vhost.serverName != null then vhost.serverName else n;
          in
          if fclib.utils.isHostname host then
            acc
            // {
              "nginx_https_${n}" = {
                notification = "HTTPS certificate check failed for vhost ${n}";
                # We're using a timeout of 15 seconds because 10 seconds is the timeout
                # that will trigger if DNS issues occur and giving the check a higher
                # timeout allows us to see those. Otherwise they get hidden behind
                # a generic timeout message.
                # Note that we assume that the certificate is reachable via port 443.
                # Other configurations might need overrides for the sensu check command.
                command = "check_http -p 443 -S --sni -C 25,14 -H ${host} -t 15";
                interval = 600;
              };
            }
          else
            acc
        ) { } (lib.attrNames vhostsWithTLS))
        # Add certificate file checks for non-ACME hosts specified in nginx config.
        # ACME certificates in general (nginx enableACME or others) are covered in platform/acme.nix.
        // (lib.foldl' (
          acc: n:
          let
            vhost = nonAcmeVhostsWithTLS.${n};
            host = if vhost.serverName != null then vhost.serverName else n;
          in
          if fclib.utils.isHostname host then
            acc
            // {
              "ssl_cert_nginx_${n}" = {
                notification = "SSL certificate for non-ACME nginx vhost ${n} is invalid or will expire soon";
                command = "sudo ${checkCert} ${vhost.sslCertificate} ${host}";
                interval = 3600;
              };
            }
          else
            acc
        ) { } (lib.attrNames nonAcmeVhostsWithTLS));

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        flyingcircus.passwordlessSudoRules = [
          {
            commands = [ (lib.getExe nginxCheckConfig) ];
            groups = [ "sensuclient" ];
          }
          # sensuclient also needs check-tls-cert but that rule already defined in
          # nixos/platform/acme.nix.
        ];

        services.nginx =
          let
            effectiveVirtualHosts = lib.recursiveUpdate {
              # Set our listen ports for the nginx internal status page
              localhost.listen = fclib.mkPlatform (
                [
                  {
                    addr = "127.0.0.1";
                    port = 81;
                  }
                ]
                ++ lib.optionals config.networking.enableIPv6 [
                  {
                    addr = "[::1]";
                    port = 81;
                  }
                ]
              );
            } cfg.virtualHosts;
          in
          {
            enable = true;
            package = fclib.mkPlatform pkgs.nginxLegacyCrypt;
            appendConfig = mainConfig;
            # We run gixy as sensu check
            validateConfigFile = false;
            enableReload = true;
            commonHttpConfig = ''
              ${baseHttpConfig}

              # === User-provided config from ${localCfgDir}/*.conf ===
              ${localHttpConfig}

              # === Config from flyingcircus.services.nginx ===
              ${cfg.httpConfig}
            '';

            eventsConfig = ''
              worker_connections 4096;
              multi_accept on;
            '';
            recommendedGzipSettings = true;
            recommendedOptimisation = true;
            recommendedProxySettings = true;
            recommendedTlsSettings = true;
            serverNamesHashBucketSize = fclib.mkPlatform 64;
            statusPage = true;
            virtualHosts = effectiveVirtualHosts;
            defaultListenAddresses = fclib.mkPlatform cfg.defaultListenAddresses;
          };

        # We want logs readable for anyone
        systemd.services.nginx.serviceConfig.LogsDirectoryMode = fclib.mkOverrideUpstreamModule "0755";
        systemd.services.nginx.serviceConfig.UMask = fclib.mkOverrideUpstreamModule "0022";

        services.logrotate.settings =
          let
            commonRotate = {
              rotate = cfg.rotateLogs;
              create = "0644 nginx nginx";
              su = "nginx nginx";
              frequency = "daily";
            };
          in
          {
            "/var/log/nginx/modsec_*.log" = {
              # need higher prio, because more-specific match.
              # Our platform header options use priority 900, we need to chose a
              # higher number here for using them.
              ignoreduplicates = true;
              priority = 901;
              copytruncate = true;
            }
            // commonRotate;
            "nginx" = commonRotate;
          };

        # Z: Recursively change permissions if they already exist.
        systemd.tmpfiles.rules = [
          "d /etc/local/nginx/modsecurity 2775 nginx service"
          # Clean up whatever logrotate may have missed three days later.
          "d /var/log/nginx 0755 ${nginxCfg.user} nginx ${toString (cfg.rotateLogs + 3)}d"
          "Z /var/log/nginx/* - ${nginxCfg.user} nginx"
        ]
        # d: Create temp subdirs if they don't exist and clean up files after 10 days.
        ++ map (subdir: ''
          d /var/cache/nginx/${subdir} 0700 nginx nginx 10d
          Z /var/cache/nginx/${subdir} 0700 nginx nginx
        '') tempSubdirs;

        flyingcircus.localConfigDirs.nginx = {
          dir = "/etc/local/nginx";
          user = "nginx";
        };

        environment.systemPackages = [
          nginxShowConfig
          nginxCheckConfig
        ];
      }

      (lib.mkIf (!builtins.isNull lokiServer) {
        systemd.services.alloy = lib.mkIf config.services.alloy.enable {
          reloadTriggers = [ config.environment.etc."alloy/syslog_nginx.alloy".source ];
          serviceConfig.SupplementaryGroups = [ "nginx" ];
        };

        environment.etc."alloy/syslog_nginx.alloy".text = ''
          loki.source.syslog "syslog_nginx" {
            listener {
              address = "127.0.0.1:51893"
              protocol = "udp"
              syslog_format = "rfc3164"
            }

            forward_to = [loki.write.fcio_rg_loki.receiver]
          }
        '';
      })
    ]
  );
}
