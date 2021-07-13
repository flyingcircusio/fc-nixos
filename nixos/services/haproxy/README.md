The Haproxy service can be configured by adding `/etc/local/haproxy/*.conf`
files in the HAproxy format as well as from custom Nix Configuration Options.

The local plain configuration files are enabled by default and can be disabled
by configuring `flyingcircus.services.haproxy.enableLocalPlainConfig`. The
structured Nix Configuration Options are disabled by default and can be enabled
by configuring `flyingcircus.services.haproxy.enableStructuredConfig`.

The haproxy service module allow you to generate a haproxy configuration from structured nix values.

You have several available options under `flyingcircus.services.haproxy` which are defined in `config-options.nix`:

```
enable
enableLocalPlainConfig (default true)
enableStructuredConfig (default false)
global
global.daemon
global.chroot
global.user
global.group
global.extraConfig
defaults
defaults.mode
defaults.options
defaults.timeout
defaults.balance
defaults.extraConfig
listen
listen.<name>.mode
listen.<name>.timeout
listen.<name>.options
listen.<name>.binds
listen.<name>.default_backend
listen.<name>.balance
listen.<name>.servers
listen.<name>.extraConfig
frontend
frontend.<name>.mode
frontend.<name>.timeout
frontend.<name>.options
frontend.<name>.binds
frontend.<name>.extraConfig
backend
backend.<name>.mode
backend.<name>.timeout
backend.<name>.options
backend.<name>.default_backend
backend.<name>.balance
backend.<name>.servers
backend.<name>.extraConfig
extraConfig
```

Example configurations:


Old default configuration:
```haproxy
global
  daemon
  chroot /var/empty
  maxconn 4096
  log localhost local2
defaults
  mode http
  log global
  option httplog
  option dontlognull
  option http-server-close
  timeout connect 5s
  timeout client 30s    # should be equal to server timeout
  timeout server 30s    # should be equal to client timeout
  timeout queue 25s     # discard requests sitting too long in the queue
listen http-in
  bind 127.0.0.1:8002
  bind ::1:8002
  default_backend be
backend be
  server localhost localhost:8080
```

```nix
{
  flyingcircus.services.haproxy = {
    enable = true;
    global = {
      daemon = true;
      chroot = "/var/empty";
      maxconn = 4096;
      extraConfig = ''
        log localhost local2
      '';
    };
    defaults = {
      mode = "http";
      options = [
        "httplog"
        "dontlognull"
        "http-server-close"
      ];
      timeouts = {
        connect = "5s";
        client = "30s"; # should be equal to server timeout
        server = "30s"; # should be equal to client timeout
        queue = "25s"; # discard requests sitting too long in the queue
      };
    };
    frontend = {
      http-in = {
        binds = [ "127.0.0.1:8002" "::1:8002" ];
        default_backend = "be";
      };
    };
    backend = {
      be = {
        servers = [ "localhost localhost:8080" ];
      };
    };
  };
}
```

Example 2:

Kubernetes frontend:

```haproxy
defaults
    balance leastconn

listen headless-web-service-http
    bind [2a02:238:f030:1c2::10b6]:80
    mode http
    server-template svc 3 headless-web-service.default.svc.cluster.local:80 check resolvers cluster init-addr none

listen lb-web-service-http
    bind [2a02:238:f030:1c2::10b6]:80
    mode http
    server-template pod 3 *.lb-web-service.default.svc.cluster.local:80 check resolvers cluster init-addr none
    # fallback
    server-template svc 1 lb-web-service.default.svc.cluster.local:80 check resolvers cluster init-addr none backup
```

In nixos:
```nix
{
  flyingcircus.services.haproxy = {
    enable = true;
    defaults = {
      extraConfig = "balance leastconn"; # You can also do this with `balance="leastconn";` now
    };
    listen = {
      "headless-web-service-http" = {
        mode = "http";
        binds = [
          "[2a02:238:f030:1c2::10b6]:80"
        ];
        extraConfig = ''
          server-template svc 3 headless-web-service.default.svc.cluster.local:80 check resolvers cluster init-addr none
        '';
      };
      "lb-web-service-http" = {
        binds = [
          "[2a02:238:f030:1c2::10b6]:80"
        ];
        mode = "http";
        extraConfig = ''
          server-template pod 3 *.lb-web-service.default.svc.cluster.local:80 check resolvers cluster init-addr none
          # fallback
          server-template svc 1 lb-web-service.default.svc.cluster.local:80 check resolvers cluster init-addr none backup
        '';
      };
    };
  };
}
```

Which generates this. Note that there are some defaults still in the config.

```haproxy
global
  daemon
  chroot /var/empty
  user haproxy
  group haproxy
  maxconn 4096
  log localhost local2
  # Increase buffers for large URLs
  tune.bufsize 131072
  tune.maxrewrite 65536
defaults
  mode http
  option httplog
  option dontlognull
  option http-server-close
  timeout client 30s
  timeout connect 5s
  timeout queue 25s
  timeout server 30s
  balance leastconn
listen headless-web-service-http
  mode http
  bind [2a02:238:f030:1c2::10b6]:80
  server-template svc 3 headless-web-service.default.svc.cluster.local:80 check resolvers cluster init-addr none
listen lb-web-service-http
  mode http
  bind [2a02:238:f030:1c2::10b6]:80
  server-template pod 3 *.lb-web-service.default.svc.cluster.local:80 check resolvers cluster init-addr none
  # fallback
  server-template svc 1 lb-web-service.default.svc.cluster.local:80 check resolvers cluster init-addr none backup
backend be
  server localhost localhost:8080
```

---
