# This replaces the NixOS nginx module.
# Taken from upstream nixos-19.03.
# Modifications:
# * Support config reloading without restart.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nginx;
  certs = config.security.acme.certs;
  vhostsConfigs = mapAttrsToList (vhostName: vhostConfig: vhostConfig) virtualHosts;
  acmeEnabledVhosts = filter (vhostConfig: vhostConfig.enableACME && vhostConfig.useACMEHost == null) vhostsConfigs;
  virtualHosts = mapAttrs (vhostName: vhostConfig:
    let
      serverName = if vhostConfig.serverName != null
        then vhostConfig.serverName
        else vhostName;
    in
    vhostConfig // {
      inherit serverName;
    } // (optionalAttrs vhostConfig.enableACME {
      sslCertificate = "${certs.${serverName}.directory}/fullchain.pem";
      sslCertificateKey = "${certs.${serverName}.directory}/key.pem";
      sslTrustedCertificate = "${certs.${serverName}.directory}/full.pem";
    }) // (optionalAttrs (vhostConfig.useACMEHost != null) {
      sslCertificate = "${certs.${vhostConfig.useACMEHost}.directory}/fullchain.pem";
      sslCertificateKey = "${certs.${vhostConfig.useACMEHost}.directory}/key.pem";
      sslTrustedCertificate = "${certs.${vhostConfig.useACMEHost}.directory}/fullchain.pem";
    })
  ) cfg.virtualHosts;
  enableIPv6 = config.networking.enableIPv6;

  recommendedProxyConfig = pkgs.writeText "nginx-recommended-proxy-headers.conf" ''
    proxy_set_header        Host $host;
    proxy_set_header        X-Real-IP $remote_addr;
    proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header        X-Forwarded-Proto $scheme;
    proxy_set_header        X-Forwarded-Host $host;
    proxy_set_header        X-Forwarded-Server $host;
    proxy_set_header        Accept-Encoding "";
  '';

  upstreamConfig = toString (flip mapAttrsToList cfg.upstreams (name: upstream: ''
    upstream ${name} {
      ${toString (flip mapAttrsToList upstream.servers (name: server: ''
        server ${name} ${optionalString server.backup "backup"};
      ''))}
      ${upstream.extraConfig}
    }
  ''));

  awkFormat = builtins.toFile "awkFormat-nginx.awk" ''
    awk -f
    {sub(/^[ \t]+/,"");idx=0}
    /\{/{ctx++;idx=1}
    /\}/{ctx--}
    {id="";for(i=idx;i<ctx;i++)id=sprintf("%s%s", id, "\t");printf "%s%s\n", id, $0}
  '';

  configFile = pkgs.runCommand "nginx.conf" {} (''
    awk -f ${awkFormat} ${pre-configFile} | sed '/^\s*$/d' > $out
  '');

  pre-configFile = pkgs.writeText "pre-nginx.conf" ''
    user ${cfg.user} ${cfg.group};
    error_log ${cfg.logError};
    pid /run/nginx/nginx.pid;

    ${cfg.config}

    ${optionalString (cfg.eventsConfig != "" || cfg.config == "") ''
    events {
      ${cfg.eventsConfig}
    }
    ''}

    ${optionalString (cfg.httpConfig == "" && cfg.config == "") ''
    http {
      include ${cfg.package}/conf/mime.types;
      include ${cfg.package}/conf/fastcgi.conf;
      include ${cfg.package}/conf/uwsgi_params;

      ${optionalString (cfg.resolver.addresses != []) ''
        resolver ${toString cfg.resolver.addresses} ${optionalString (cfg.resolver.valid != "") "valid=${cfg.resolver.valid}"};
      ''}
      ${upstreamConfig}

      ${optionalString (cfg.recommendedOptimisation) ''
        # optimisation
        sendfile on;
        tcp_nopush on;
        tcp_nodelay on;
        keepalive_timeout 65;
        types_hash_max_size 2048;
      ''}

      ssl_protocols ${cfg.sslProtocols};
      ssl_ciphers ${cfg.sslCiphers};
      ${optionalString (cfg.sslDhparam != null) "ssl_dhparam ${cfg.sslDhparam};"}

      ${optionalString (cfg.recommendedTlsSettings) ''
        ssl_session_cache shared:SSL:42m;
        ssl_session_timeout 23m;
        ssl_ecdh_curve secp384r1;
        ssl_prefer_server_ciphers on;
        ssl_stapling on;
        ssl_stapling_verify on;
      ''}

      ${optionalString (cfg.recommendedGzipSettings) ''
        gzip on;
        gzip_disable "msie6";
        gzip_proxied any;
        gzip_comp_level 5;
        gzip_types
          application/atom+xml
          application/javascript
          application/json
          application/xml
          application/xml+rss
          image/svg+xml
          text/css
          text/javascript
          text/plain
          text/xml;
        gzip_vary on;
      ''}

      ${optionalString (cfg.recommendedProxySettings) ''
        proxy_redirect          off;
        proxy_connect_timeout   90;
        proxy_send_timeout      90;
        proxy_read_timeout      90;
        proxy_http_version      1.0;
        include ${recommendedProxyConfig};
      ''}

      ${optionalString (cfg.mapHashBucketSize != null) ''
        map_hash_bucket_size ${toString cfg.mapHashBucketSize};
      ''}

      ${optionalString (cfg.mapHashMaxSize != null) ''
        map_hash_max_size ${toString cfg.mapHashMaxSize};
      ''}

      ${optionalString (cfg.serverNamesHashBucketSize != null) ''
        server_names_hash_bucket_size ${toString cfg.serverNamesHashBucketSize};
      ''}

      ${optionalString (cfg.serverNamesHashMaxSize != null) ''
        server_names_hash_max_size ${toString cfg.serverNamesHashMaxSize};
      ''}

      # $connection_upgrade is used for websocket proxying
      map $http_upgrade $connection_upgrade {
          default upgrade;
          '''      close;
      }
      client_max_body_size ${cfg.clientMaxBodySize};

      server_tokens ${if cfg.serverTokens then "on" else "off"};

      ${cfg.commonHttpConfig}

      ${vhosts}

      ${optionalString cfg.statusPage ''
        server {
          listen 127.0.0.1:80;
          ${optionalString enableIPv6 "listen [::1]:80;" }

          server_name localhost;

          location /nginx_status {
            stub_status on;
            access_log off;
            allow 127.0.0.1;
            ${optionalString enableIPv6 "allow ::1;"}
            deny all;
          }
        }
      ''}

      ${cfg.appendHttpConfig}
    }''}

    ${optionalString (cfg.httpConfig != "") ''
    http {
      include ${cfg.package}/conf/mime.types;
      include ${cfg.package}/conf/fastcgi.conf;
      include ${cfg.package}/conf/uwsgi_params;
      ${cfg.httpConfig}
    }''}

    ${cfg.appendConfig}
  '';

  vhosts = concatStringsSep "\n" (mapAttrsToList (vhostName: vhost:
    let
        onlySSL = vhost.onlySSL || vhost.enableSSL;
        hasSSL = onlySSL || vhost.addSSL || vhost.forceSSL;

        defaultListen =
          if vhost.listen != [] then vhost.listen
          else ((optionals hasSSL (
            singleton                    { addr = vhost.listenAddress; port = 443; ssl = true; }
            ++ optional enableIPv6 { addr = vhost.listenAddress6;    port = 443; ssl = true; }
          )) ++ optionals (!onlySSL) (
            singleton                    { addr = vhost.listenAddress; port = 80;  ssl = false; }
            ++ optional enableIPv6 { addr = vhost.listenAddress6;    port = 80;  ssl = false; }
          ));

        hostListen =
          if vhost.forceSSL
            then filter (x: x.ssl) defaultListen
            else defaultListen;

        listenString = { addr, port, ssl, extraParameters ? [], ... }:
          "listen ${addr}:${toString port} "
          + optionalString ssl "ssl "
          + optionalString (ssl && vhost.http2) "http2 "
          + optionalString vhost.default "default_server "
          + optionalString (extraParameters != []) (concatStringsSep " " extraParameters)
          + ";";

        redirectListen = filter (x: !x.ssl) defaultListen;

        acmeLocation = optionalString (vhost.enableACME || vhost.useACMEHost != null) ''
          location /.well-known/acme-challenge {
            ${optionalString (vhost.acmeFallbackHost != null) "try_files $uri @acme-fallback;"}
            root ${vhost.acmeRoot};
            auth_basic off;
          }
          ${optionalString (vhost.acmeFallbackHost != null) ''
            location @acme-fallback {
              auth_basic off;
              proxy_pass http://${vhost.acmeFallbackHost};
            }
          ''}
        '';

      in ''
        ${optionalString vhost.forceSSL ''
          server {
            ${concatMapStringsSep "\n" listenString redirectListen}

            server_name ${vhost.serverName} ${concatStringsSep " " vhost.serverAliases};
            ${acmeLocation}
            location / {
              return 301 https://$host$request_uri;
            }
          }
        ''}

        server {
          ${concatMapStringsSep "\n" listenString hostListen}
          server_name ${vhost.serverName} ${concatStringsSep " " vhost.serverAliases};
          ${acmeLocation}
          ${optionalString (vhost.root != null) "root ${vhost.root};"}
          ${optionalString (vhost.globalRedirect != null) ''
            return 301 http${optionalString hasSSL "s"}://${vhost.globalRedirect}$request_uri;
          ''}
          ${optionalString hasSSL ''
            ssl_certificate ${vhost.sslCertificate};
            ssl_certificate_key ${vhost.sslCertificateKey};
          ''}
          ${optionalString (hasSSL && vhost.sslTrustedCertificate != null) ''
            ssl_trusted_certificate ${vhost.sslTrustedCertificate};
          ''}

          ${optionalString (vhost.basicAuthFile != null || vhost.basicAuth != {}) ''
            auth_basic secured;
            auth_basic_user_file ${if vhost.basicAuthFile != null then vhost.basicAuthFile else mkHtpasswd vhostName vhost.basicAuth};
          ''}

          ${mkLocations vhost.locations}

          ${vhost.extraConfig}
        }
      ''
  ) virtualHosts);
  mkLocations = locations: concatStringsSep "\n" (map (config: ''
    location ${config.location} {
      ${optionalString (config.proxyPass != null && !cfg.proxyResolveWhileRunning)
        "proxy_pass ${config.proxyPass};"
      }
      ${optionalString (config.proxyPass != null && cfg.proxyResolveWhileRunning) ''
        set $nix_proxy_target "${config.proxyPass}";
        proxy_pass $nix_proxy_target;
      ''}
      ${optionalString config.proxyWebsockets ''
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
      ''}
      ${optionalString (config.index != null) "index ${config.index};"}
      ${optionalString (config.tryFiles != null) "try_files ${config.tryFiles};"}
      ${optionalString (config.root != null) "root ${config.root};"}
      ${optionalString (config.alias != null) "alias ${config.alias};"}
      ${config.extraConfig}
      ${optionalString (config.proxyPass != null && cfg.recommendedProxySettings) "include ${recommendedProxyConfig};"}
    }
  '') (sortProperties (mapAttrsToList (k: v: v // { location = k; }) locations)));
  mkBasicAuth = vhostName: authDef: let
    htpasswdFile = pkgs.writeText "${vhostName}.htpasswd" (
      concatStringsSep "\n" (mapAttrsToList (user: password: ''
        ${user}:{PLAIN}${password}
      '') authDef)
    );
  in ''
    auth_basic secured;
    auth_basic_user_file ${htpasswdFile};
  '';

  mkHtpasswd = vhostName: authDef: pkgs.writeText "${vhostName}.htpasswd" (
    concatStringsSep "\n" (mapAttrsToList (user: password: ''
      ${user}:{PLAIN}${password}
    '') authDef)
  );

  checkConfigCmd = "${cfg.package}/bin/nginx -t -c ${configFile}";

  nginxReloadMaster =
    let
      pkill = "${pkgs.procps}/bin/pkill";
    in
    pkgs.writeScriptBin "nginx-reload-master" ''
      set -e
      echo "Starting new nginx master process..."
      ${pkill} -USR2 -F /run/nginx/nginx.pid

      for x in {1..10}; do
          echo "Waiting for new master process to appear, try $x..."
          sleep 1
          if [[ -s /run/nginx/nginx.pid && -s /run/nginx/nginx.pid.oldbin ]]; then
              echo "Stopping old nginx workers..."
              ${pkill} -WINCH -F /run/nginx/nginx.pid.oldbin
              echo "Stopping old nginx master process..."
              ${pkill} -QUIT -F /run/nginx/nginx.pid.oldbin
              echo "Nginx master process replacement complete."
              exit 0
          fi
      done

      echo "Warning: new master process did not start."
      echo "This can be caused by changes to listen directives that are incompatible with the running nginx master process."
      echo "Check journalctl -eu nginx and try systemctl restart nginx to activate changes."
      exit 1
    '';

in

{
  imports = [
    (mkRemovedOptionModule [ "services" "nginx" "stateDir" ] ''
      The Nginx log directory has been moved to /var/log/nginx, the cache directory
      to /var/cache/nginx. The option services.nginx.stateDir has been removed.
    '')
  ];

  options = {
    services.nginx = {
      enable = mkEnableOption "Nginx Web Server";

      statusPage = mkOption {
        default = false;
        type = types.bool;
        description = "
          Enable status page reachable from localhost on http://127.0.0.1/nginx_status.
        ";
      };

      recommendedTlsSettings = mkOption {
        default = false;
        type = types.bool;
        description = "
          Enable recommended TLS settings.
        ";
      };

      recommendedOptimisation = mkOption {
        default = false;
        type = types.bool;
        description = "
          Enable recommended optimisation settings.
        ";
      };

      recommendedGzipSettings = mkOption {
        default = false;
        type = types.bool;
        description = "
          Enable recommended gzip settings.
        ";
      };

      recommendedProxySettings = mkOption {
        default = false;
        type = types.bool;
        description = "
          Enable recommended proxy settings.
        ";
      };

      package = mkOption {
        default = pkgs.nginxStable;
        defaultText = "pkgs.nginxStable";
        type = types.package;
        description = "
          Nginx package to use. This defaults to the stable version. Note
          that the nginx team recommends to use the mainline version which
          available in nixpkgs as <literal>nginxMainline</literal>.
        ";
      };

      logError = mkOption {
        default = "stderr";
        description = "
          Configures logging.
          The first parameter defines a file that will store the log. The
          special value stderr selects the standard error file. Logging to
          syslog can be configured by specifying the “syslog:” prefix.
          The second parameter determines the level of logging, and can be
          one of the following: debug, info, notice, warn, error, crit,
          alert, or emerg. Log levels above are listed in the order of
          increasing severity. Setting a certain log level will cause all
          messages of the specified and more severe log levels to be logged.
          If this parameter is omitted then error is used.
        ";
      };

      preStart =  mkOption {
        type = types.lines;
        default = "";
        description = "
          Shell commands executed before the service's nginx is started.
        ";
      };

      config = mkOption {
        default = "";
        description = "
          Verbatim nginx.conf configuration.
          This is mutually exclusive with the structured configuration
          via virtualHosts and the recommendedXyzSettings configuration
          options. See appendConfig for appending to the generated http block.
        ";
      };

      appendConfig = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Configuration lines appended to the generated Nginx
          configuration file. Commonly used by different modules
          providing http snippets. <option>appendConfig</option>
          can be specified more than once and it's value will be
          concatenated (contrary to <option>config</option> which
          can be set only once).
        '';
      };

      commonHttpConfig = mkOption {
        type = types.lines;
        default = "";
        example = ''
          resolver 127.0.0.1 valid=5s;

          log_format myformat '$remote_addr - $remote_user [$time_local] '
                              '"$request" $status $body_bytes_sent '
                              '"$http_referer" "$http_user_agent"';
        '';
        description = ''
          With nginx you must provide common http context definitions before
          they are used, e.g. log_format, resolver, etc. inside of server
          or location contexts. Use this attribute to set these definitions
          at the appropriate location.
        '';
      };

      httpConfig = mkOption {
        type = types.lines;
        default = "";
        description = "
          Configuration lines to be set inside the http block.
          This is mutually exclusive with the structured configuration
          via virtualHosts and the recommendedXyzSettings configuration
          options. See appendHttpConfig for appending to the generated http block.
        ";
      };

      eventsConfig = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Configuration lines to be set inside the events block.
        '';
      };

      appendHttpConfig = mkOption {
        type = types.lines;
        default = "";
        description = "
          Configuration lines to be appended to the generated http block.
          This is mutually exclusive with using config and httpConfig for
          specifying the whole http block verbatim.
        ";
      };

      user = mkOption {
        type = types.str;
        default = "nginx";
        description = "User account under which nginx runs.";
      };

      group = mkOption {
        type = types.str;
        default = "nginx";
        description = "Group account under which nginx runs.";
      };

      serverTokens = mkOption {
        type = types.bool;
        default = false;
        description = "Show nginx version in headers and error pages.";
      };

      clientMaxBodySize = mkOption {
        type = types.str;
        default = "10m";
        description = "Set nginx global client_max_body_size.";
      };

      sslCiphers = mkOption {
        type = types.str;
        default = "EECDH+aRSA+AESGCM:EDH+aRSA:EECDH+aRSA:+AES256:+AES128:+SHA1:!CAMELLIA:!SEED:!3DES:!DES:!RC4:!eNULL";
        description = "Ciphers to choose from when negotiating tls handshakes.";
      };

      sslProtocols = mkOption {
        type = types.str;
        default = "TLSv1.2 TLSv1.3";
        example = "TLSv1 TLSv1.1 TLSv1.2 TLSv1.3";
        description = "Allowed TLS protocol versions.";
      };

      sslDhparam = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/path/to/dhparams.pem";
        description = "Path to DH parameters file.";
      };

      proxyResolveWhileRunning = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Resolves domains of proxyPass targets at runtime
          and not only at start, you have to set
          services.nginx.resolver, too.
        '';
      };

      mapHashBucketSize = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        description = ''
            Sets the bucket size for the map variables hash tables. Default
            value depends on the processor’s cache line size.
          '';
      };

      mapHashMaxSize = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        description = ''
            Sets the maximum size of the map variables hash tables.
          '';
      };

      serverNamesHashBucketSize = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        description = ''
            Sets the bucket size for the server names hash tables. Default
            value depends on the processor’s cache line size.
          '';
      };

      serverNamesHashMaxSize = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        description = ''
            Sets the maximum size of the server names hash tables.
          '';
      };

      resolver = mkOption {
        type = types.submodule {
          options = {
            addresses = mkOption {
              type = types.listOf types.str;
              default = [];
              example = literalExample ''[ "[::1]" "127.0.0.1:5353" ]'';
              description = "List of resolvers to use";
            };
            valid = mkOption {
              type = types.str;
              default = "";
              example = "30s";
              description = ''
                By default, nginx caches answers using the TTL value of a response.
                An optional valid parameter allows overriding it
              '';
            };
          };
        };
        description = ''
          Configures name servers used to resolve names of upstream servers into addresses
        '';
        default = {};
      };

      upstreams = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            servers = mkOption {
              type = types.attrsOf (types.submodule {
                options = {
                  backup = mkOption {
                    type = types.bool;
                    default = false;
                    description = ''
                      Marks the server as a backup server. It will be passed
                      requests when the primary servers are unavailable.
                    '';
                  };
                };
              });
              description = ''
                Defines the address and other parameters of the upstream servers.
              '';
              default = {};
            };
            extraConfig = mkOption {
              type = types.lines;
              default = "";
              description = ''
                These lines go to the end of the upstream verbatim.
              '';
            };
          };
        });
        description = ''
          Defines a group of servers to use as proxy target.
        '';
        default = {};
      };

      virtualHosts = mkOption {
        type = types.attrsOf (types.submodule (import ./vhost-options.nix {
          inherit config lib;
        }));
        default = {
          localhost = {};
        };
        example = literalExample ''
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
    };
  };

  config = mkIf cfg.enable ( mkMerge [
    {
      # TODO: test user supplied config file pases syntax test

      warnings =
      let
        deprecatedSSL = name: config: optional config.enableSSL
        ''
          config.services.nginx.virtualHosts.<name>.enableSSL is deprecated,
          use config.services.nginx.virtualHosts.<name>.onlySSL instead.
        '';

      in flatten (mapAttrsToList deprecatedSSL virtualHosts);

      assertions =
      let
        hostOrAliasIsNull = l: l.root == null || l.alias == null;
      in [
        {
          assertion = all (host: all hostOrAliasIsNull (attrValues host.locations)) (attrValues virtualHosts);
          message = "Only one of nginx root or alias can be specified on a location.";
        }

        {
          assertion = all (conf: with conf;
            !(addSSL && (onlySSL || enableSSL)) &&
            !(forceSSL && (onlySSL || enableSSL)) &&
            !(addSSL && forceSSL)
          ) (attrValues virtualHosts);
          message = ''
            Options services.nginx.service.virtualHosts.<name>.addSSL,
            services.nginx.virtualHosts.<name>.onlySSL and services.nginx.virtualHosts.<name>.forceSSL
            are mutually exclusive.
          '';
        }

        {
          assertion = all (conf: !(conf.enableACME && conf.useACMEHost != null)) (attrValues virtualHosts);
          message = ''
            Options services.nginx.service.virtualHosts.<name>.enableACME and
            services.nginx.virtualHosts.<name>.useACMEHost are mutually exclusive.
          '';
        }
      ];

      environment.systemPackages = [ nginxReloadMaster ];

      systemd.services.nginx = {
        description = "Nginx Web Server";
        wantedBy = [ "multi-user.target" ];
        wants = concatLists (map (vhostConfig: ["acme-${vhostConfig.serverName}.service" "acme-selfsigned-${vhostConfig.serverName}.service"]) acmeEnabledVhosts);
        after = [ "network.target" ] ++ map (vhostConfig: "acme-selfsigned-${vhostConfig.serverName}.service") acmeEnabledVhosts;
        before = map (vhostConfig: "acme-${vhostConfig.serverName}.service") acmeEnabledVhosts;
        stopIfChanged = false;
        preStart =
          ''
          ${cfg.preStart}
          ln -sf ${configFile} /run/nginx/config
          ln -sfT ${cfg.package} /run/nginx/package
        '';
        reload = ''
          echo "Reload triggered, checking config file..."
          # Check if the new config is valid
          ${checkConfigCmd} || rc=$?

          if [[ -n $rc ]]; then
            echo "Error: Not restarting / reloading because of config errors."
            echo "New configuration not activated!"
            # We must use 0 as exit code, otherwise systemd would kill the nginx process.
            # This is a bug in systemd: https://github.com/systemd/systemd/issues/11238
            exit 0
          fi

          ln -sf ${configFile} /run/nginx/config

          # Check if the package changed
          current_pkg=$(readlink /run/nginx/package)

          if [[ $current_pkg != ${cfg.package} ]]; then
            echo "Nginx package changed: $current_pkg -> ${cfg.package}."
            ln -sfT ${cfg.package} /run/nginx/package

            if [[ -s /run/nginx/nginx.pid ]]; then
              if ${nginxReloadMaster}/bin/nginx-reload-master; then
                echo "Master process replacement completed."
              else
                echo "Master process replacement failed, trying again on next reload."
                ln -sfT $current_pkg /run/nginx/package
              fi
            else
              # We are still running an old version that didn't write a PID file or something is broken.
              # We can only force a restart now.
              echo "Warning: cannot replace master process because PID is missing. Restarting Nginx now..."
              ${pkgs.coreutils}/bin/kill -QUIT $MAINPID
            fi

          else
            # Package unchanged, we only need to change the configuration.
            echo "Reloading nginx config now."

            # Check journal for errors after the reload signal.
            datetime=$(date +'%Y-%m-%d %H:%M:%S')
            ${pkgs.coreutils}/bin/kill -HUP $MAINPID

            # Give Nginx some time to try changing the configuration.
            sleep 3

            if [[ $(journalctl --since="$datetime" -u nginx -q -g '\[emerg\]') != "" ]]; then
              echo "Warning: Possible failure when changing to new configuration."
              echo "This happens when changes to listen directives are incompatible with the running nginx master process."
              echo "Try systemctl restart nginx to activate the new config."
            fi
          fi
        '';
        reloadIfChanged = true;

        serviceConfig = {
          Type = "forking";
          PIDFile = "/run/nginx/nginx.pid";
          ExecStart = "/run/nginx/package/bin/nginx -c /run/nginx/config";
          Restart = "always";
          # Logs directory and mode
          LogsDirectory = "nginx";
          LogsDirectoryMode = "0755";
          # X- options are ignored by systemd.
          # To show the last running config, use:
          # cat `systemctl cat nginx | grep "X-ConfigFile" | cut -d= -f2`
          X-ConfigFile = configFile;
          # To check the current config file:
          # `systemctl cat nginx | grep "X-CheckConfigCmd" | cut -d= -f2`
          X-CheckConfigCmd = checkConfigCmd;
        };
      };

      systemd.tmpfiles.rules = [
        "d /var/cache/nginx 0750 nginx nginx"
        "d /run/nginx 0755 root root"
      ];

      system.activationScripts.nginx-reload-check = lib.stringAfter [ "wrappers" ] ''
        if ${pkgs.procps}/bin/pgrep nginx &> /dev/null; then
          nginx_check_msg=$(${checkConfigCmd} 2>&1) || rc=$?

          if [[ -n $rc ]]; then
            printf "\033[0;31mWarning: \033[0mNginx config is invalid at this point:\n$nginx_check_msg\n"
            echo Reload may still work if missing Let\'s Encrypt SSL certs are the reason, for example.
            echo Please check the output of journalctl -eu nginx
          fi
        fi
      '';

      security.acme.certs = filterAttrs (n: v: v != {}) (
        let
          acmePairs = map (vhostConfig: { name = vhostConfig.serverName; value = {
              user = cfg.user;
              group = lib.mkDefault cfg.group;
              webroot = vhostConfig.acmeRoot;
              extraDomains = genAttrs vhostConfig.serverAliases (alias: null);
              postRun = ''
                systemctl reload nginx
              '';
            }; }) acmeEnabledVhosts;
        in
          listToAttrs acmePairs
      );
    }

    (mkIf (cfg.user == "nginx") {
      users.users.nginx = {
        group = cfg.group;
        uid = config.ids.uids.nginx;
      };
    })

    (mkIf (cfg.group == "nginx") {
      users.groups.nginx = {
        gid = config.ids.gids.nginx;
      };
    })

  ]);
}
