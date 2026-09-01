# Webgateway (NGINX, HAProxy) { #nixos-webgateway }

This role provides a stack of components that enables you to serve a web
application via HTTP. In addition, you can do load balancing and configure
failover support.

## Versions

- HAProxy: 3.3.x
- Nginx: 1.30.x

## Role architecture

The webgateway role uses:

- the [nginx](http://nginx.org/) web server
- the [HAProxy](http://www.haproxy.org/) load balancer and proxy server

We provide basic config for both services. You will have to add custom
configuration to serve your site.

Both services support config reload and changing the binary without downtime.

!!! note
    Although we install nginx and HAProxy, there is no need to use them
    both. Since there is no connection between them w.r.t configuration, you can
    still use only one of them and leave the other one as is.

### How we differ from what you are used to

Here is how we differ from what you already know from common Linux distributions
and how you are used to configure, start, stop and maintain these packages.

- **configuration file locations:**

  We do not edit files in `/etc/nginx/*` or `/etc/haproxy/*`, respectively.
  Since we use NixOS, files have to be edited in `/etc/local`, followed by a
  NixOS rebuild which copies them into the
  Nix store and activates the new configuration. To do so, run the command
  `sudo fc-manage switch`

- **service control:**

  We use `systemd` to control processes. You can use familiar commands
  like `sudo systemctl restart nginx` to control services.
  However, remember that invoking `sudo fc-manage switch` is
  necessary to put configuration changes into effect. A simple restart is not
  sufficient. For further information, see [nixos-local](../platform/local.md#nixos-local).

## HAProxy

### Structured configuration using Nix expressions

All haproxy options are mapped into structured NixOS options. A basic example
looks like this:

```nix
# /etc/local/nixos/myservice.nix
{ ... }:
{
  flyingcircus.services.haproxy = {
    enableStructuredConfig = true;

    listen."http-in" = {
      binds = [ "127.0.0.1:8002" "::1:8002" ];
      default_backend = "myapp";
    };

    backend."myapp" = {
      servers = [
        "appserver1 localhost:8001"
        "appserver2 localhost:8001"
        "appserver3 localhost:8001"
      ];
    };

  };
}
```


### Unstructured configuration using config snippets

Put your HAProxy configuration in `/etc/local/haproxy/haproxy.cfg`.
You can find an example config at `/etc/local/haproxy/haproxy.cfg.example`.
Please refer to the [official documentation](https://docs.haproxy.org/2.9/configuration.html)
for more details.

If you need more than just one centralized configuration file,
you can use multiple files named `*.cfg` in the local configuration directory.
They will get merged along in alphabetical order.

Changes to your custom config will cause haproxy to reload without downtime on
the next fc-manage run.

The final haproxy config file can be shown with: `haproxy-show-config`.

## nginx { #nixos-nginx }

We provide basic config. You have to configure at least one virtual host.

Changes to your custom config will cause nginx to reload without downtime on
the next fc-manage run if the config is valid. It will display a warning if
invalid settings are found in the nginx config.

Note that changes to listen directives that are incompatible with the running config
may require a manual Nginx restart that drops connections.
Using `reuseport` can avoid such situations (see below).

After building it with `sudo fc-manage switch`, the final nginx config file
can be shown with: `nginx-show-config`

You can check if the config is valid with: `nginx-check-config`.
The script also warns about potential security issues with your current config.

The recommended method is structured configuration via Nix code as described in the next section.
Alternatively, we still support plain nginx config files in `/etc/local/nginx`. \
Support for structured JSON config was removed in platform version 24.11.

### Structured Nix Configuration (recommended)

!!! note
    We plan to deprecate our custom-prefix `flyingcircus.services.nginx` options in favour of the very similar NixOS
    upstream `services.nginx` options. \
    When migrating from JSON-config or starting from scratch, consider already using `services.nginx` for your
    configuration.

Define Nginx virtual hosts with the NixOS option `services.nginx.virtualHosts`.

See [nixos-custom-modules](../platform/local.md#nixos-custom-modules) for general information about writing custom NixOS
modules in `/etc/local/nixos`.

The following NixOS module defines two virtual hosts listening on all frontend
IP addresses which is the default. Requests to Port 80 are redirected to 443
which serves SSL using a managed certificate from Let's Encrypt.
`subdomain.example.com/internal` is protected by HTTP Basic Auth with an
users file automatically created for users with the login permission:

```nix
# /etc/local/nixos/nginx.nix
{ ... }:
{
  services.nginx.virtualHosts = {
    "www.example.com"  = {
      serverAliases = [ "example.com" ];
      default = true;
      enableACME = true;
      forceSSL = true;
      root = "/srv/webroot";
    };

    "subdomain.example.com" = {
      enableACME = true;
      forceSSL = true;
      extraConfig = ''
        add_header Strict-Transport-Security max-age=31536000;
        rewrite ^/old_url /new_url redirect;
        access_log /var/log/nginx/subdomain.log;
      '';
      locations = {
        "/cms" = {
          # Pass request to HAProxy, for example
          proxyPass = "http://localhost:8008";
        };
        "/internal" = {
          # Authenticate as FCIO user (user has to have login permission).
          basicAuth = "FCIO user";
          basicAuthFile = "/etc/local/htpasswd_fcio_users";
          proxyPass = "http://localhost:8008";
        };
      };
    };
  };
}
```

You can also find this example at `/etc/local/nixos/nginx.nix.example`
if the webgateway role is enabled.

In our configuration, nginx binds to all frontend IPs instead of all IPs.
This behavior can be changed with the `services.nginx.defaultListenAddresses` or `services.nginx.defaultListen`
options.

One vhost definition should set the `default` option.
Without that, the first vhost entry will be the default one.
Because we combine config from multiple files, setting an explicit default is
strongly encouraged to avoid surprises with server name matching.

We support a custom `reuseport` option for `listen` which is true by default.
The option only has an effect on the default vhost and is ignored on others.
The effect is that Nginx will start a separate socket listener for each worker.
This helps performance and allows changing listen IPs on config reload
without the need to restart Nginx.

#### HTTPS and Let's Encrypt

For SSL support with redirection from HTTP to HTTPS, use `forceSSL`.
Let's Encrypt (`enableACME`) is activated automatically if one of `forceSSL`, `onlySSL` or `addSSL`
is set to true.
Self-signed certificates are created for new vhosts before Nginx starts or reloads.
They are replaced by the proper certificates after some seconds.
A systemd timer checks the age of the certificates and renews them automatically if needed.
To use a custom certificate, set the certificate options and set `"enableACME" = false`.

#### SSL ciphers


With default settings, the following ciphers are available:

<!--
We use IANA names for the ciphers here.
-->

TLS 1.3:

- TLS_AES_128_GCM_SHA256
- TLS_AES_256_GCM_SHA384
- TLS_CHACHA20_POLY1305_SHA256

TLS 1.2:

- TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
- TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
- TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256

with the

- X25519MLKEM768
- X25519
- P-256
- P-384

TLS groups.

To use ciphers based on RSA for legacy clients, an RSA key must be
used for the certificates. Note that this disables the ciphers listed above
and reduces performance. Please avoid using RSA certificates!

Overriding the key type can be done per certificate:

```nix
security.acme.certs."test.fcio.net".keyType = "rsa4096";
```

When an RSA server certificate is in use the following ciphers are activated:

- `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256`
- `TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384`
- `TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256`

Using two certificates to support both kinds of ciphers is possible with Nginx
but needs manual configuration.

For ciphers using DHE, an RSA certificate must be used. *dhparams* must be generated and set:

```nix
security.dhparams.enable = true;
security.dhparams.params.nginx = {};
services.nginx.sslDhparam = config.security.dhparams.params.nginx.path;
```

DHE TLS ciphers are deprecated and will be removed in fc-nixos 26.11 together with the `services.dhparams` module.
Please migrate to ECDHE (RFC 8422, 2018) and Hybrid PQ (draft-ietf-tls-ecdhe-mlkem, 2026) key exchange algorithms.

This enables the following TLS ciphers:

- `TLS_DHE_RSA_WITH_AES_128_GCM_SHA256`
- `TLS_DHE_RSA_WITH_AES_256_GCM_SHA384`
- `TLS_DHE_RSA_WITH_CHACHA20_POLY1305_SHA256`

The DH param file is located at `/var/lib/dhparams/nginx.pem`.
This path can be referenced from Nix code by `security.dhparams.params.nginx.path` as shown in the config example above.

The [services.nginx.sslCiphers](https://search.flyingcircus.io/search/options?q=services.nginx.sslCiphers&channel=fc-26.05-dev#services.nginx.sslCiphers)
option can be used to change the cipher list.

If you enable weaker ciphers, you should also set `services.nginx.legacyTlsSettings` to true
and `services.nginx.recommendedTlsSettings` to false.

This sets `ssl_prefer_server_ciphers on` so better ciphers at the beginning of
the cipher list are used if possible.

### Plain Configuration (old)

If you want to use plain Nginx configuration add the config file as `/etc/local/nginx/nginx.conf`.
It has to contain at least one `server` block declaration as described in [the official documentation](https://www.nginx.com/resources/admin-guide/nginx-web-server/). Your files
will then be integrated with our nginx base config. Therefore, please omit
the http clause. It is already set by the base config.

See `/etc/local/nginx/example-configuration` for an example and `/etc/local/nginx/README.txt`.

### Logging

nginx' access logs are stored by default in `/var/log/nginx/access.log`.
Individual log files for virtual hosts can be defined in the corresponding
configuration sections. We use the *anonymized* log format for GDPR
conformance by default.

Add this to an `extraConfig` block in Nix config or your plain nginx config:

```
access_log /var/log/nginx/app.log;
```

nginx' error logs go to systemd's journal by default. To view them, use
`journalctl(1)` as usual, e.g.:

```console
$ journalctl --since -1h -u nginx
```

### Basic auth with legacy password hashes { #nixos-webgateway-nginx-legacy-crypt }

Starting with NixOS 23.05, nginx uses a version of `libxcrypt` which only supports algorithms marked as [`strong`](https://github.com/besser82/libxcrypt/blob/v4.4.33/lib/hashes.conf#L48). You will encounter errors when password files for HTTP basic auth use algorithms like MD5 (hash prefix`$1$`) and SHA256 (`$5$`). Password hashes using these algorithms should be replaced as soon as possible.

If you still need them on 25.05, use the Nginx package which still supports all algorithms:

~~~
# /etc/local/nixos/nginx-legacy-crypt.nix
{ pkgs, ... }:
{
  services.nginx.package = pkgs.nginxLegacyCrypt;
}
~~~

A package alias under the name `nginxLegacyCrypt` is already available in our NixOS 22.11 release, enabling seamless platform upgrades with the same configuration.


### Rate limiting

There are a few scenarios where you may need to rate limit connections going
to nginx. One aspect can be DOS protection against some specific attacks like
"[rapid reset](https://www.cisa.gov/news-events/alerts/2023/10/10/http2-rapid-reset-vulnerability-cve-2023-44487)". We generally keep nginx updated so that you will benefit from
general counter measures against those kinds of attacks.

However, in some scenarios rate limiting may be necessary to fend off attackers.
As rate limits need to be carefully adjusted to your specific application
we do not enable rate limits on our platform by default.

The options available to control rate limiting in your nginx instance are:

~~~
# /etc/local/nixos/nginx-rate-limiting.nix
{ pkgs, ... }:
{
  flyingcircus.services.nginx.rateLimit = {
    enable = true;
    maxConcurrent = 200;
    maxRequestsPerSecond = 50;
    burst = 500;
  };
}
~~~
