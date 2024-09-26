# Note that Nginx is reloaded when config, unit file or package change.
# Future changes may require a full Nginx restart to become active.
# We can use systemd.services.nginx.restartTriggers to force a restart.
# This may also affect other services that use reloading.
{ lib, config, pkgs, ... }:

with builtins; with lib;

let
  cfg = config.flyingcircus.services.nginx;
  nginxCfg = config.services.nginx;
  fclib = config.fclib;

  nginxCheckConfig = pkgs.writeScriptBin "nginx-check-config" ''

  '';

  nginxShowConfig = pkgs.writeScriptBin "nginx-show-config" ''
    cat /etc/nginx/nginx.conf
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

  mkVanillaVhostFromFCVhost = name: vhost: let
    servername = if vhost.serverName != null then vhost.serverName else name;
  in (removeAttrs vhost [ "emailACME" "listenAddress" "listenAddress6" ]) // {
    extraConfig = vhost.extraConfig + (lib.optionalString cfg.logPerVirtualHost ''
      access_log /var/log/nginx/access-${servername}.log;
      error_log /var/log/nginx/error-${servername}.log;
    '');
  };

  virtualHosts = lib.mapAttrs mkVanillaVhostFromFCVhost cfg.virtualHosts;

  # only email setting supported at the moment
  acmeSettings =
    lib.mapAttrs (name: val: { email = val.emailACME; })
    (lib.filterAttrs (_: val: val ? emailACME && val.emailACME != null ) cfg.virtualHosts);

  acmeVhosts = (lib.filterAttrs (_: val: val ? enableACME ) cfg.virtualHosts);

  mainConfig = ''
    worker_processes ${toString (fclib.currentCores 1)};
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

  hostsWithLegacyListenOptions =
    filter
      (x: x.laExtra != [])
      (mapAttrsToList
        (hostname: host: let
          laExtra = filter (x: x != null) [ host.listenAddress host.listenAddress6 ];
        in { inherit hostname host laExtra; })
        cfg.virtualHosts);

in
{

  imports = [ ./base-module.nix ];

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

    # FIXME: use upstream
    virtualHosts = mkOption {
      type = let
        vhost = import ./vhost-options.nix {
          inherit config lib;
        };
      in types.attrsOf (types.submodule ({ config, ... }: {
        options = vhost.options // {
          listenAddress = mkOption {
            type = types.nullOr types.str;
            description = ''
              IPv4 address to listen on.
              If neither <option>listenAddress</option> nor <option>listenAddress6</option> is set,
              the service listens on the frontend addresses.

              If you need more options, use <option>listen</option>.
              If you want to configure any number of IPs use <literal>listenAddresses</literal>.
            '';
            default = null;
          };

          listenAddress6 = mkOption {
            type = types.nullOr types.str;
            description = ''
              IPv6 address to listen on.
              If neither <option>listenAddress</option> nor <option>listenAddress6</option> is set,
              the service listens on the frontend addresses.

              If you need more options, use <option>listen</option>.
              If you want to configure any number of IPs use <literal>listenAddresses</literal>.
            '';
            default = null;
          };

          emailACME = mkOption {
            type = types.nullOr types.str;
            description = ''
              Set the contact address for Let's Encrypt (certificate expiry, policy changes).
              Defaults to none.
            '';
            default = null;
          };

          enableACME = vhost.options.enableACME // {
            default = config.onlySSL or false || config.enableSSL or false || config.addSSL or false || config.forceSSL or false;
          };

          listenAddresses = vhost.options.listenAddresses // {
            default = if (config.listenAddress != null || config.listenAddress6 != null)
              then filter (x: x != null) [
                config.listenAddress
                config.listenAddress6
              ]
              else cfg.defaultListenAddresses;
          };
        };
      }));
      default = {};
      example = literalExpression ''
        {
          "hydra.example.com" = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = "http://localhost:3000";
            };
          };
        };
      '';
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

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions =
        map
          ({ hostname, host, laExtra }: {
            assertion = host.listenAddresses == laExtra;
            message = ''
              ${hostname}: listenAddress(6) and the new array-format listenAddresses cannot be mixed
              Please exclusively use listenAddresses instead:
                listenAddresses = [ ${escapeShellArgs host.listenAddresses} ];
            '';
          })
          hostsWithLegacyListenOptions;

      warnings = (map
          ({ hostname, host, laExtra }: ''
            ${hostname}: listenAddress and listenAddress6 are deprecated and will be removed in 24.05.
            Please exclusively use listenAddresses instead:
              listenAddresses = [ ${escapeShellArgs host.listenAddresses} ];
          '')
          hostsWithLegacyListenOptions);

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

        "local/nginx/example-configuration".text =
          import ./example-plain-config.nix { inherit config lib; };

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
          "${pkgs.libmodsecurity.src}/unicode.mapping";

        "local/nixos/nginx.nix.example".source = ./example-nixos-module.nix;
      };

      flyingcircus.services.telegraf.inputs = {
        nginx = [ {
          urls = [ "http://localhost:81/nginx_status" ];
        } ];
      };

      flyingcircus.services.sensu-client.checks = {

        nginx_config = {
          notification = "Nginx configuration check problems";
          command = "/run/wrappers/bin/sudo /run/current-system/sw/bin/nginx-check-config";
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

      };

      networking.firewall.allowedTCPPorts = [ 80 443 ];

      security.acme.certs = acmeSettings;

      flyingcircus.passwordlessSudoRules = [
        {
          commands = [ "/run/current-system/sw/bin/nginx-check-config" ];
          groups = [ "sensuclient" ];
        }
      ];

      services.nginx = {
        enable = true;
        package = fclib.mkPlatform pkgs.nginxLegacyCrypt;
        appendConfig = mainConfig;
        appendHttpConfig = ''
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
        inherit virtualHosts;
      };

      services.logrotate.settings = let
      commonRotate = {
          rotate = cfg.rotateLogs;
          create = "0644 ${nginxCfg.user} nginx";
          su = "${nginxCfg.user} nginx";
        };
        in {
        "/var/log/nginx/modsec_*.log" = {
          # need higher prio, because more-specific match.
          # Our platform header options use priority 900, we need to chose a
          # higher number here for using them.
          ignoreduplicates = true;
          priority = 901;
          copytruncate = true;
        } // commonRotate;
        "/var/log/nginx/*.log" = {
          postrotate = ''
            systemctl kill nginx -s USR1 --kill-who=main || systemctl reload nginx
            chown ${nginxCfg.user}:nginx /var/log/nginx/*
          '';
        } // commonRotate;
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
      ''
      ) tempSubdirs;

      flyingcircus.localConfigDirs.nginx = {
        dir = "/etc/local/nginx";
        user = "nginx";
      };

      environment.systemPackages = [
        nginxShowConfig
      ];

    })
  ];
}
