{ config, lib }:

let
  fclib = config.fclib;

  listenStatements =
    builtins.concatStringsSep "\n    "
      (lib.concatMap
        (formatted_addr: [
          "listen ${formatted_addr}:80 default_server reuseport;"
          "listen ${formatted_addr}:443 ssl default_server reuseport;"])
        (map
          (addr:
            if fclib.isIp4 addr then addr else "[${addr}]")
          (fclib.listenAddresses "ethfe")));

in
''
  # Example nginx configuration for the Flying Circus. Copy this file into
  # 'mydomain.conf' and edit. You'll certainly want to replace www.example.com
  # with something more specific. Please note that configuration files must end
  # with '.conf' to be active. Reload with `sudo fc-manage --build`.

  upstream @varnish {
      server localhost:8008;
      keepalive 100;
  }

  upstream @haproxy {
      server localhost:8002;
      keepalive 10;
  }

  upstream @app {
      server localhost:8080;
  }

  server {
      ${listenStatements}

      # The first server name listed is the primary name. We remommend against
      # using a wildcard server name (*.example.com) as primary.
      server_name www.example.com example.com;

      # Redirect to primary server name (makes URLs unique).
      if ($host != $server_name) {
          rewrite . $scheme://$server_name$request_uri redirect;
      }

      # Enable SSL. SSL parameters like cipher suite have sensible defaults.
      #ssl_certificate /etc/nginx/local/www.example.com.crt;
      #ssl_certificate_key /etc/nginx/local/www.example.com.key;

      # Enable the following block if you want to serve HTTPS-only.
      #if ($server_port != 443) {
      #    rewrite . https://$server_name$request_uri redirect;
      #}
      #add_header Strict-Transport-Security max-age=31536000;

      location / {
          # Example for passing virtual hosting details to Zope apps
          #rewrite (.*) /VirtualHostBase/http/$server_name:$server_port/APP/VirtualHostRoot$1 break;
          #proxy_pass http://@varnish;

          # enable mod_security
          #ModSecurityEnabled on;
          #ModSecurityConfig /etc/local/nginx/modsecurity/modsecurity_includes.conf;
      }
  }
''
