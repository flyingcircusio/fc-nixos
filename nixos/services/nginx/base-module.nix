# This replaces the NixOS nginx module.
# Taken from upstream nixos-20.09.
# Modifications:
# * Support config reloading without restart.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nginx;
  certs = config.security.acme.certs;
  vhostsConfigs = mapAttrsToList (vhostName: vhostConfig: vhostConfig) virtualHosts;
  acmeEnabledVhosts = filter (vhostConfig: vhostConfig.enableACME || vhostConfig.useACMEHost != null) vhostsConfigs;
  dependentCertNames = unique (map (hostOpts: hostOpts.certName) acmeEnabledVhosts);
  sslServiceNames = map (certName: "acme-${certName}") dependentCertNames;
  sslServices = map (serviceName: "${serviceName}.service") sslServiceNames;
  sslSelfSignedServiceNames = map (certName: "acme-selfsigned-${certName}") dependentCertNames;
  sslSelfSignedServices = map (serviceName: "${serviceName}.service") sslSelfSignedServiceNames;
  sslTargetNames = map (certName: "acme-finished-${certName}") dependentCertNames;
  sslTargets = map (targetName: "${targetName}.target") sslTargetNames;
  virtualHosts = mapAttrs (vhostName: vhostConfig:
    let
      serverName = if vhostConfig.serverName != null
        then vhostConfig.serverName
        else vhostName;
      certName = if vhostConfig.useACMEHost != null
        then vhostConfig.useACMEHost
        else serverName;
    in
    vhostConfig // {
      inherit serverName certName;
    } // (optionalAttrs (vhostConfig.enableACME || vhostConfig.useACMEHost != null) {
      sslCertificate = "${certs.${certName}.directory}/fullchain.pem";
      sslCertificateKey = "${certs.${certName}.directory}/key.pem";
      sslTrustedCertificate = "${certs.${certName}.directory}/chain.pem";
    })
  ) cfg.virtualHosts;
  enableIPv6 = config.networking.enableIPv6;

  recommendedProxyConfig = pkgs.writeText "nginx-recommended-proxy-headers.conf" ''
    proxy_set_header        Host $host;
    proxy_set_header        X-Real-IP $remote_addr;
    proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header        X-Forwarded-Proto $scheme;
    proxy_set_header        X-Forwarded-Host $host;
    proxy_set_header        X-Forwarded-Server $server_name;
  '';

  upstreamConfig = toString (flip mapAttrsToList cfg.upstreams (name: upstream: ''
    upstream ${name} {
      ${toString (flip mapAttrsToList upstream.servers (name: server: ''
        server ${name} ${optionalString server.backup "backup"};
      ''))}
      ${upstream.extraConfig}
    }
  ''));

  commonHttpConfig = ''
      # The mime type definitions included with nginx are very incomplete, so
      # we use a list of mime types from the mailcap package, which is also
      # used by most other Linux distributions by default.
      include ${pkgs.mailcap}/etc/nginx/mime.types;
      include ${cfg.package}/conf/fastcgi.conf;
      include ${cfg.package}/conf/uwsgi_params;

      default_type application/octet-stream;
  '';

  writeNginxConfig = name: text: pkgs.runCommandLocal name {
    inherit text;
    passAsFile = [ "text" ];
  } /* sh */ ''
    # nginx-config-formatter has an error - https://github.com/1connect/nginx-config-formatter/issues/16
    ${pkgs.gawk}/bin/awk -f ${pkgs.writers.awkFormatNginx} "$textPath" | ${pkgs.gnused}/bin/sed '/^\s*$/d' > $out
    # XXX: The gixy security check fails even for low-impact issues and the builder
    # cuts off the output which makes finding the problem annoying.
    # ${pkgs.gixy}/bin/gixy $out
  '';

  configFile = writeNginxConfig "nginx.conf" ''
    user ${cfg.user} ${cfg.group};

    pid /run/nginx/nginx.pid;
    error_log ${cfg.logError};

    ${cfg.config}

    ${optionalString (cfg.eventsConfig != "" || cfg.config == "") ''
    events {
      ${cfg.eventsConfig}
    }
    ''}

    ${optionalString (cfg.httpConfig == "" && cfg.config == "") ''
    http {
      ${commonHttpConfig}

      ${optionalString (cfg.resolver.addresses != []) ''
        resolver ${toString cfg.resolver.addresses} ${optionalString (cfg.resolver.valid != "") "valid=${cfg.resolver.valid}"} ${optionalString (!cfg.resolver.ipv6) "ipv6=off"};
      ''}
      ${upstreamConfig}

      ${optionalString (cfg.recommendedOptimisation) ''
        # optimisation
        sendfile on;
        tcp_nopush on;
        tcp_nodelay on;
        keepalive_timeout 65;
        types_hash_max_size 4096;
      ''}

      ssl_protocols ${cfg.sslProtocols};
      ${optionalString (cfg.sslCiphers != null) "ssl_ciphers ${cfg.sslCiphers};"}
      ${optionalString (cfg.sslDhparam != null) "ssl_dhparam ${cfg.sslDhparam};"}

      ${optionalString (cfg.recommendedTlsSettings) ''
        # Keep in sync with https://ssl-config.mozilla.org/#server=nginx&config=intermediate

        ssl_session_timeout 1d;
        ssl_session_cache shared:SSL:10m;
        # Breaks forward secrecy: https://github.com/mozilla/server-side-tls/issues/135
        ssl_session_tickets off;
        # We don't enable insecure ciphers by default, so this allows
        # clients to pick the most performant, per https://github.com/mozilla/server-side-tls/issues/260
        ssl_prefer_server_ciphers off;

        # OCSP stapling
        ssl_stapling on;
        ssl_stapling_verify on;
      ''}

      ${optionalString (cfg.legacyTlsSettings) ''
        # Keep in sync with https://ssl-config.mozilla.org/#server=nginx&config=old

        ssl_session_timeout 1d;
        ssl_session_cache shared:SSL:10m;
        ssl_session_tickets off;
        ssl_prefer_server_ciphers on;

        # OCSP stapling
        ssl_stapling on;
        ssl_stapling_verify on;
      ''}

      ${optionalString (cfg.recommendedGzipSettings) ''
        gzip on;
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
          # Conditional v6 handling, see:
          # https://stackoverflow.com/a/15101745
          # Also: use a non-80 port as we still want to be able to bind
          # 0.0.0.0:80 and/or [::1]:80 without causing reload issues.
          listen 127.0.0.1:81;
          ${optionalString enableIPv6 "listen [::1]:81;" }

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
      ${commonHttpConfig}
      ${cfg.httpConfig}
    }''}

    ${cfg.appendConfig}
  '';

  configPath = "/etc/nginx/nginx.conf";
  runningPackagePath = "/etc/nginx/running-package";
  wantedPackagePath = "/etc/nginx/wanted-package";

  vhosts = concatStringsSep "\n" (mapAttrsToList (vhostName: vhost:
    let
        onlySSL = vhost.onlySSL || vhost.enableSSL;
        hasSSL = onlySSL || vhost.addSSL || vhost.forceSSL;

        defaultListen =
          if vhost.listen != [] then vhost.listen
          else
            # This combines with our setting of "net.ipv6.bindv6only" to 0
            # and the choice that nginx 1.13+ automatically enforces
            # [::0] being ipv6only=on.
            # We decided for this combination based on the recommendations
            # in https://serverfault.com/questions/638367/do-you-need-separate-ipv4-and-ipv6-listen-directives-in-nginx
            let addrs = if vhost.listenAddresses != [] then vhost.listenAddresses else (
              [ "0.0.0.0" ] ++ optional enableIPv6 "[::0]"
            );
            in
          optionals (hasSSL || vhost.rejectSSL) (map (addr: { inherit addr; port = 443; ssl = true; }) addrs)
          ++ optionals (!onlySSL) (map (addr: { inherit addr; port = 80; ssl = false; }) addrs);

        hostListen =
          if vhost.forceSSL
            then filter (x: x.ssl) defaultListen
            else defaultListen;

        listenString = { addr, port, ssl, reuseport ? true, extraParameters ? [], ... }:
          "listen ${addr}:${toString port} "
          + optionalString ssl "ssl "
          + optionalString (ssl && vhost.http2) "http2 "
          + optionalString vhost.default "default_server "
          + optionalString (vhost.default && reuseport) "reuseport "
          + optionalString (extraParameters != []) (concatStringsSep " " extraParameters)
          + ";"
          + (if ssl && vhost.http3 then ''
          # UDP listener for **QUIC+HTTP/3
          listen ${addr}:${toString port} http3 reuseport;
          # Advertise that HTTP/3 is available
          add_header Alt-Svc 'h3=":443"';
          # Sent when QUIC was used
          add_header QUIC-Status $quic;
          '' else "");

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

          ${mkBasicAuth vhostName vhost}

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
      ${concatStringsSep "\n"
        (mapAttrsToList (n: v: ''fastcgi_param ${n} "${v}";'')
          (optionalAttrs (config.fastcgiParams != {})
            (defaultFastcgiParams // config.fastcgiParams)))}
      ${optionalString (config.index != null) "index ${config.index};"}
      ${optionalString (config.tryFiles != null) "try_files ${config.tryFiles};"}
      ${optionalString (config.root != null) "root ${config.root};"}
      ${optionalString (config.alias != null) "alias ${config.alias};"}
      ${optionalString (config.return != null) "return ${config.return};"}
      ${config.extraConfig}
      ${optionalString (config.proxyPass != null && cfg.recommendedProxySettings) "include ${recommendedProxyConfig};"}
      ${mkBasicAuth "sublocation" config}
    }
  '') (sortProperties (mapAttrsToList (k: v: v // { location = k; }) locations)));

  mkBasicAuth = name: zone: optionalString (zone.basicAuthFile != null || zone.basicAuth != {}) (let
    auth_file = if zone.basicAuthFile != null
      then zone.basicAuthFile
      else mkHtpasswd name zone.basicAuth;
  in ''
    auth_basic secured;
    auth_basic_user_file ${auth_file};
  '');
  mkHtpasswd = name: authDef: pkgs.writeText "${name}.htpasswd" (
    concatStringsSep "\n" (mapAttrsToList (user: password: ''
      ${user}:{PLAIN}${password}
    '') authDef)
  );

  checkConfigCmd = ''${wantedPackagePath}/bin/nginx -t -c ${configPath}'';

  nginxCheckConfig = pkgs.writeScriptBin "nginx-check-config" ''
    #!${pkgs.runtimeShell}
    echo "Running built-in Nginx config validation (must pass in order to activate a config)..."
    ${checkConfigCmd} || exit 2
    echo "Running gixy security checker (just informational)..."
    ${pkgs.gixy}/bin/gixy ${configPath} || exit 1
  '';

  nginxReloadConfig = pkgs.writeScriptBin "nginx-reload" ''
    #!${pkgs.runtimeShell} -e
    echo "Reload triggered, checking config file..."
    # Check if the new config is valid
    ${checkConfigCmd} || rc=$?
    chown -R ${cfg.masterUser}:${cfg.group} /var/log/nginx

    if [[ -n $rc ]]; then
      echo "Error: Not restarting / reloading because of config errors."
      echo "New configuration not activated!"
      exit 1
    fi

    # Check if the package changed
    running_pkg=$(readlink ${runningPackagePath})
    wanted_pkg=$(readlink ${wantedPackagePath})

    if [[ $running_pkg != $wanted_pkg ]]; then
      echo "Nginx package changed: $running_pkg -> $wanted_pkg."
      ln -sfT $wanted_pkg ${runningPackagePath}

      if [[ -s /run/nginx/nginx.pid ]]; then
        if ${nginxReloadMaster}/bin/nginx-reload-master; then
          echo "Master process replacement completed."
        else
          echo "Master process replacement failed, trying again on next reload."
          ln -sfT $running_pkg ${runningPackagePath}
        fi
      else
        # We are still running an old version that didn't write a PID file or something is broken.
        # We can only force a restart now.
        echo "Warning: cannot replace master process because PID is missing. Restarting Nginx now..."
        kill -QUIT $MAINPID
      fi

    else
      # Package unchanged, we only need to change the configuration.
      echo "Reloading nginx config now."

      # Check journal for errors after the reload signal.
      datetime=$(date +'%Y-%m-%d %H:%M:%S')
      kill -HUP $MAINPID

      # Give Nginx some time to try changing the configuration.
      sleep 3

      if [[ $(journalctl --since="$datetime" -u nginx -q -g '\[emerg\]') != "" ]]; then
        echo "Warning: Possible failure when changing to new configuration."
        echo "This happens when changes to listen directives are incompatible with the running nginx master process."
        echo "Try systemctl restart nginx to activate the new config."
        exit 1
      fi
    fi
  '';
  nginxReloadMaster =
    pkgs.writeScriptBin "nginx-reload-master" ''
      #!${pkgs.runtimeShell} -e
      echo "Starting new nginx master process..."
      kill -USR2 $(< /run/nginx/nginx.pid)

      for x in {1..10}; do
          echo "Waiting for new master process to appear, try $x..."
          sleep 1
          if [[ -s /run/nginx/nginx.pid && -s /run/nginx/nginx.pid.oldbin ]]; then
              echo "Stopping old nginx workers..."
              kill -WINCH $(< /run/nginx/nginx.pid.oldbin)
              echo "Stopping old nginx master process..."
              kill -QUIT $(< /run/nginx/nginx.pid.oldbin)
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
          Enable recommended TLS settings (Mozilla intermediate).
        ";
      };

      legacyTlsSettings = mkOption {
        default = false;
        type = types.bool;
        description = "
          Enable legacy TLS settings for very old clients (Mozilla old).
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
        apply = p: p.override {
          modules = p.modules ++ cfg.additionalModules;
        };
        description = "
          Nginx package to use. This defaults to the stable version. Note
          that the nginx team recommends to use the mainline version which
          available in nixpkgs as <literal>nginxMainline</literal>.
        ";
      };

      additionalModules = mkOption {
        default = [];
        type = types.listOf (types.attrsOf types.anything);
        example = literalExample "[ pkgs.nginxModules.brotli ]";
        description = ''
          Additional <link xlink:href="https://www.nginx.com/resources/wiki/modules/">third-party nginx modules</link>
          to install. Packaged modules are available in
          <literal>pkgs.nginxModules</literal>.
        '';
      };

      logError = mkOption {
        default = "stderr";
        type = types.str;
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
        type = types.str;
        default = "";
        description = ''
          Verbatim <filename>nginx.conf</filename> configuration.
          This is mutually exclusive to any other config option for
          <filename>nginx.conf</filename> except for
          <itemizedlist>
          <listitem><para><xref linkend="opt-services.nginx.appendConfig" />
          </para></listitem>
          <listitem><para><xref linkend="opt-services.nginx.httpConfig" />
          </para></listitem>
          <listitem><para><xref linkend="opt-services.nginx.logError" />
          </para></listitem>
          </itemizedlist>

          If additional verbatim config in addition to other options is needed,
          <xref linkend="opt-services.nginx.appendConfig" /> should be used instead.
        '';
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

      streamConfig = mkOption {
        type = types.lines;
        default = "";
        example = ''
          server {
            listen 127.0.0.1:53 udp reuseport;
            proxy_timeout 20s;
            proxy_pass 192.168.0.1:53535;
          }
        '';
        description = "
          Configuration lines to be set inside the stream block.
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

      masterUser = mkOption {
        type = types.str;
        default = "nginx";
        description = ''
          User account under which nginx master process runs.
          Must be either the same as `user` or set to root.
        '';
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
        # Keep in sync with https://ssl-config.mozilla.org/#server=nginx&config=intermediate
        default = "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
        description = "Ciphers to choose from when negotiating TLS handshakes.";
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
            ipv6 = mkOption {
              type = types.bool;
              default = true;
              description = ''
                By default, nginx will look up both IPv4 and IPv6 addresses while resolving.
                If looking up of IPv6 addresses is not desired, the ipv6=off parameter can be
                specified.
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
              example = { "127.0.0.1:8000" = {}; };
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
        example = literalExample ''
          "backend_server" = {
            servers = { "127.0.0.1:8000" = {}; };
            extraConfig = ''''
              keepalive 16;
            '''';
          };
        '';
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

  imports = [
    (mkRemovedOptionModule [ "services" "nginx" "stateDir" ] ''
      The Nginx log directory has been moved to /var/log/nginx, the cache directory
      to /var/cache/nginx. The option services.nginx.stateDir has been removed.
    '')
  ];

  config = mkIf cfg.enable {
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

      {
        assertion = !(cfg.legacyTlsSettings && cfg.recommendedTlsSettings);
        message = ''
          Options services.nginx.service.legacyTlsSettings and
          services.nginx.virtualHosts.recommendedTlsSettings are mutually exclusive.
        '';
      }

      {
        assertion = (cfg.user == cfg.masterUser) || (cfg.masterUser == "root");
        message = ''
          services.nginx.user (is ${cfg.user}) must be the same as services.nginx.masterUser (is ${cfg.masterUser})
          or services.nginx.masterUser must be root.
        '';
      }
    ];
    environment.systemPackages = [ nginxReloadMaster nginxCheckConfig ];

    environment.etc."nginx/nginx.conf".source = configFile;

    systemd.services = {

      nginx =
      let
        preStartScript = pkgs.writeScript "nginx-pre-start" ''
          #!${pkgs.runtimeShell} -e
          ln -sfT $(readlink -f ${wantedPackagePath}) ${runningPackagePath}
          chown ${cfg.masterUser}:${cfg.group} -R /var/log/nginx
        '';
      in {
        description = "Nginx Web Server";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        stopIfChanged = false;
        startLimitIntervalSec = 1 * 60; # 1 minute

        serviceConfig = {
          Type = "forking";
          PIDFile = "/run/nginx/nginx.pid";
          ExecStartPre = [
            "+${preStartScript}"
          ];
          ExecStart = "${runningPackagePath}/bin/nginx -c ${configPath}";
          ExecReload = "+${nginxReloadConfig}/bin/nginx-reload";
          Restart = "always";
          RestartSec = "10s";
          # User and group
          User = cfg.masterUser;
          Group = cfg.group;
          # Runtime directory and mode
          RuntimeDirectory = "nginx";
          RuntimeDirectoryMode = "0755";
          # Cache directory and mode
          CacheDirectory = "nginx";
          CacheDirectoryMode = "0775";
          # Logs directory and mode
          LogsDirectory = "nginx";
          LogsDirectoryMode = "0755";
          # This limits the capabilities to the given list but does not grant
          # anything by default if root is the master user.
          # Nginx does the right thing: it gives all of these capabilities to the
          # master process but none to the workers. This means that the master
          # can access certificates even if the permissions wouldn't allow it
          # but workers cannot access arbitrary files without proper permissions.
          CapabilityBoundingSet = [
            "CAP_NET_BIND_SERVICE"
            "CAP_DAC_READ_SEARCH"
            "CAP_SYS_RESOURCE"
            "CAP_SETUID"
            "CAP_SETGID"
            "CAP_CHOWN"
          ];
          # If the master user is not root, it needs some automatically granted
          # capabilities to be able to bind to privileged ports, for example.
          # This is the same list as in the upstream Nginx module.
          AmbientCapabilities =
            lib.optionals (cfg.masterUser != "root") [
            "CAP_NET_BIND_SERVICE"
            "CAP_SYS_RESOURCE"
          ];

          # Security
          NoNewPrivileges = true;
          # Sandboxing
          ProtectSystem = "strict";
          ProtectHome = mkDefault true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectHostname = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
          LockPersonality = true;
          MemoryDenyWriteExecute = !(builtins.any (mod: (mod.allowMemoryWriteExecute or false)) pkgs.nginx.modules);
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          PrivateMounts = true;
          # System Call Filtering
          SystemCallArchitectures = "native";
        };
      };
      # postRun hooks on cert renew can't be used to restart Nginx since renewal
      # runs as the unprivileged acme user. sslTargets are added to wantedBy + before
      # which allows the acme-finished-$cert.target to signify the successful updating
      # of certs end-to-end.
      nginx-config-reload = {
        wants = [ "nginx.service" ];
        wantedBy = sslServices ++ [ "multi-user.target" ];
        # Before the finished targets, after the renew services.
        # This service might be needed for HTTP-01 challenges, but we only want to confirm
        # certs are updated _after_ config has been reloaded.
        before = sslTargets;
        after = sslServices;
        restartTriggers = [ configFile ];
        # Block reloading if not all certs exist yet.
        # Happens when config changes add new vhosts/certs.
        unitConfig.ConditionPathExists = optionals (sslServices != []) (map (certName: certs.${certName}.directory + "/fullchain.pem") dependentCertNames);
        serviceConfig = {
          Type = "oneshot";
          TimeoutSec = 120;
          Restart = "on-abnormal";
          ExecCondition = "/run/current-system/systemd/bin/systemctl -q is-active nginx.service";
          ExecStart = "/run/current-system/systemd/bin/systemctl reload nginx.service";
        };
      };
    } //
      # Nginx needs to be started in order to be able to request certificates
      # (it's hosting the acme challenge after all)
      # This fixes https://github.com/NixOS/nixpkgs/issues/81842
      lib.listToAttrs
        (map
          (name: lib.nameValuePair name { after = [ "nginx.service" ]; })
          sslServiceNames) //
      lib.listToAttrs
        (map
          (name: lib.nameValuePair name { before = [ "nginx.service" ]; })
          sslSelfSignedServiceNames);

    systemd.targets =
      lib.listToAttrs
        (map
          (name: lib.nameValuePair name { wantedBy = [ "nginx.service" ]; })
          sslTargetNames);

    system.activationScripts.nginx-set-package = lib.stringAfter [ "etc" ] ''
      ln -sfT ${cfg.package} ${wantedPackagePath}
    '';

    system.activationScripts.nginx-reload-check = lib.stringAfter [ "nginx-set-package" ] ''
      if ${pkgs.procps}/bin/pgrep nginx &> /dev/null; then
        nginx_check_msg=$(${checkConfigCmd} 2>&1) || rc=$?

        if [[ -n $rc ]]; then
          printf "\033[0;31mWarning: \033[0mNginx config is invalid at this point:\n$nginx_check_msg\n"
          echo Reload may still work if missing Let\'s Encrypt SSL certs are the reason, for example.
          echo Please check the output of journalctl -eu nginx
        fi
      fi
    '';

    security.acme.certs = let
      acmePairs = map (vhostConfig: nameValuePair vhostConfig.serverName {
        group = mkDefault cfg.group;
        webroot = vhostConfig.acmeRoot;
        extraDomainNames = vhostConfig.serverAliases;
      # Filter for enableACME-only vhosts. Don't want to create dud certs
      }) (filter (vhostConfig: vhostConfig.useACMEHost == null) acmeEnabledVhosts);
    in listToAttrs acmePairs;

    users.users = optionalAttrs (cfg.user == "nginx") {
      nginx = {
        group = cfg.group;
        isSystemUser = true;
        uid = config.ids.uids.nginx;
      };
    };

    users.groups = optionalAttrs (cfg.group == "nginx") {
      nginx.gid = config.ids.gids.nginx;
    };

  };
}
