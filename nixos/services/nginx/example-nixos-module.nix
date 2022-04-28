{ ... }:
{
  flyingcircus.services.nginx.virtualHosts = {
    "www.example.com"  = {
      serverAliases = [ "example.com" ];
      default = true;
      forceSSL = true;
      root = "/srv/webroot";
    };

    "subdomain.example.com"  = {
      forceSSL = true;
      extraConfig = ''
        add_header Strict-Transport-Security max-age=31536000;
        rewrite ^/old_url /new_url redirect;
        access_log /var/log/nginx/subdomain.log;
      '';
      locations = {
        "/cms" = {
          # Pass request to HAProxy, for example
          proxyPass = "http://localhost:8002";
        };
        "/internal" = {
          # Authenticate as FCIO user (user has to have login permission).
          basicAuth = "FCIO user";
          basicAuthFile = "/etc/local/htpasswd_fcio_users";
          proxyPass = "http://localhost:8002";
        };
      };
    };
  };
}
