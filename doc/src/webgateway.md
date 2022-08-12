(nixos-webgateway)=

# Webgateway (NGINX, HAProxy)

This role provides a stack of components that enables you to serve a web
application via HTTP. In addition, you can do load balancing and configure
failover support.

## Versions

- HAProxy: 2.3.14
- Nginx: 1.20.2

## Role architecture

The webgateway role uses:

- the [nginx](http://nginx.org/) web server
- the [HAProxy](http://www.haproxy.org/) load balancer and proxy server

We provide basic config for both services. You will have to add custom
configuration to serve your site.

Both services support config reload and changing the binary without downtime.

:::{note}
Although we install nginx and HAProxy, there is no need to use them
both. Since there is no connection between them w.r.t configuration, you can
still use only one of them and leave the other one as is.
:::

### How we differ from what you are used to

Here is how we differ from what you already know from common Linux distributions
and how you are used to configure, start, stop and maintain these packages.

- **configuration file locations:**

  We do not edit files in `/etc/nginx/*` or `/etc/haproxy/*`, respectively.
  Since we use NixOS, files have to be edited in {file}`/etc/local`, followed by a
  NixOS rebuild which copies them into the
  Nix store and activates the new configuration. To do so, run the command
  {command}`sudo fc-manage -b`

- **service control:**

  We use {command}`systemd` to control processes. You can use familiar commands
  like {command}`sudo systemctl restart nginx` to control services.
  However, remember that invoking {command}`sudo fc-manage -b` is
  necessary to put configuration changes into effect. A simple restart is not
  sufficient. For further information, see {ref}`nixos-local`.

## HAProxy

Put your HAProxy configuration in {file}`/etc/local/haproxy/haproxy.cfg`.
You can find an example config at {file}`/etc/local/haproxy/haproxy.cfg.example`.
Please refer to the [official documentation](http://cbonte.github.io/haproxy-dconv/2.3/configuration.html)
for more details.

If you need more than just one centralized configuration file,
you can use multiple files named `*.cfg` in the local configuration directory.
They will get merged along in alphabetical order.

Changes to your custom config will cause haproxy to reload without downtime on
the next fc-manage run.

The final haproxy config file can be shown with: {command}`haproxy-show-config`.

(nixos-nginx)=

## nginx

We provide basic config. You have to configure at least one virtual host.

Changes to your custom config will cause nginx to reload without downtime on
the next fc-manage run if the config is valid. It will display a warning if
invalid settings are found in the nginx config.

Note that changes to listen directives that are incompatible with the running config
may require a manual Nginx restart that drops connections.
Using `reuseport` can avoid such situations (see below).

After building it with {command}`sudo fc-manage -b`, the final nginx config file
can be shown with: {command}`nginx-show-config`

You can check if the config is valid with: {command}`nginx-check-config`.
The script also warns about potential security issues with your current config.

The recommended method is structured configuration via Nix code as described in the next section.
We still support plain nginx config and structured JSON config in {file}`/etc/local/nginx`.

### Structured Nix Configuration (recommended)

Define Nginx virtual hosts with the NixOS option `flyingcircus.services.nginx.virtualHosts`.

See {ref}`nixos-custom-modules` for general information about writing custom NixOS
modules in {file}`/etc/local/nixos`.

The following NixOS module defines two virtual hosts listening on all frontend
IP addresses which is the default. Requests to Port 80 are redirected to 443
which serves SSL using a managed certificate from Let's Encrypt.
`subdomain.example.com/internal` is protected by HTTP Basic Auth with an
users file automatically created for users with the login permission:

```nix
# /etc/local/nixos/nginx.nix
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

You can also find this example at {file}`/etc/local/nixos/nginx.nix.example`
if the webgateway role is enabled.

Our `flyingcircus.services.nginx.virtualHosts` option supports all settings of the upstream NixOS option
[services.nginx.virtualHosts](https://search.nixos.org/options?query=services.nginx.virtualHosts.&from=0&size=50&sort=relevance)
with the difference that we bind to all frontend IPs by default instead of all interfaces.

`flyingcircus.services.nginx.virtualHosts` has the following custom settings:

- `emailACME`: set the contact address for Let's Encrypt (certificate expiry, policy changes), defaults to none.
- `listenAddresses`: List of IPv4 and quoted IPv6 addresses to bind to (default: frontend IPs).

The `listen` option overrides our defaults: the `listenAddresses` options has
no effect and no IP is used automatically in this case.

One vhost definition should set the `default` option.
Without that, the first vhost entry will be the default one.
Because we combine config from multiple files, setting an explicit default is
strongly encouraged to avoid surprises with server name matching.

We support a custom `reuseport` option for `listen` which is true by default.
The option only has an effect on the default vhost and is ignored on others.
The effect is that Nginx will start a separate socket listener for each worker.
This helps performance and allows changing listen IPs on config reload
without the need to restart Nginx.

Deprecated options:

- `listenAddress`: Single IPv4 address
- `listenAddress6`: Single IPv6 address

`listenAddresses` should be used instead.

If only one of the listenAddress\* options is given, the vhost listens only on IPv4 or IPv6.
If none of the `listenAddress*` options is given, all frontend IPs are used.
Using `listenAddresses` at the same time overrides the deprecated options.

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

TLS 1.3:

- TLS_AES_128_GCM_SHA256
- TLS_AES_256_GCM_SHA384
- TLS_CHACHA20_POLY1305_SHA256

TLS 1.2:

- TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
- TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
- TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256

To use ciphers based on RSA for legacy clients, an RSA key must be
used for the certificates. Note that this disables the ciphers listed above
and reduces performance with newer clients.

Overriding the key type can be done per certificate:

```nix
security.acme.certs."test.fcio.net".keyType = "rsa2048";
```

Using two certificates to support both kinds of ciphers is possible with Nginx
but needs manual configuration.

For ciphers using DHE, an RSA certificate must be used. *dhparams* must be generated and set:

```nix
security.dhparams.params.nginx = {};
services.nginx.sslDhparam = config.security.dhparams.params.nginx.path;
```

This enables the following TLS 1.2 ciphers:

- TLS_DHE_RSA_WITH_AES_128_GCM_SHA256
- TLS_DHE_RSA_WITH_AES_256_GCM_SHA384

The DH param file is located at /var/lib/dhparams/nginx.pem.
This path can be referenced from Nix code by `security.dhparams.params.nginx.path` as shown in the config example above.

The [services.nginx.sslCiphers](https://search.nixos.org/options?channel=21.05&show=services.nginx.sslCiphers&from=0&size=50&sort=relevance&query=sslCiphers)
option can be used to change the cipher list.

If you enable weaker ciphers, you should also set `services.nginx.legacyTlsSettings` to true
and `services.nginx.recommendedTlsSettings` to false.

This sets `ssl_prefer_server_ciphers on` so better ciphers at the beginning of
the cipher list are used if possible.

### Plain Configuration (old)

If you want to use plain Nginx configuration add the config file as {file}`/etc/local/nginx/nginx.conf`.
It has to contain at least one {command}`server` block declaration as described in [the official documentation](https://www.nginx.com/resources/admin-guide/nginx-web-server/). Your files
will then be integrated with our nginx base config. Therefore, please omit
the http clause. It is already set by the base config.

See {file}`/etc/local/nginx/example-configuration` for an example and {file}`/etc/local/nginx/README.txt`.

### JSON Configuration (old)

Although not recommended anymore, JSON config can be added to {file}`/etc/local/nginx`,
alongside with plain nginx config files. Nix config should be used instead, as described above.
JSON config supports the same options as Nix config so converting from JSON to
Nix is basically just a syntax change.

See {file}`/etc/local/nginx/README.txt` for an example and more info.

### Logging

nginx' access logs are stored by default in {file}`/var/log/nginx/access.log`.
Individual log files for virtual hosts can be defined in the corresponding
configuration sections. We use the *anonymized* log format for GDPR
conformance by default.

Add this to an `extraConfig` block in Nix config or your plain nginx config:

```
access_log /var/log/nginx/app.log;
```

nginx' error logs go to systemd's journal by default. To view them, use
{manpage}`journalctl(1)` as usual, e.g.:

```console
$ journalctl --since -1h -u nginx
```
