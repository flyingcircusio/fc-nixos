Nginx is enabled on this machine.

The recommended method is structured configuration via Nix code in `/etc/local/nixos`.
You can also find an example at `/etc/local/nixos/nginx.nix.example`.
Refer to the webgateway role documentation at
https://doc.flyingcircus.io/roles/fc-23.05-production/webgateway.html for more info.


Old configuration methods
-------------------------

We provide basic config. You can place JSON or plain Nginx config here.

Changes to your custom config will cause nginx to reload without downtime on
the next fc-manage run if the config is valid. It will display a warning if
invalid settings are found in the nginx config.

Note that changes to listen directives that are incompatible with the running config
may require a manual Nginx restart that drops connections.
Using `reuseport` can avoid such situations (see below).


After building it with `sudo fc-manage -b`, the final nginx config file
can be shown with: `nginx-show-config`

You can check if the config is valid with: `nginx-check-config`.
The script also warns about potential security issues with your current config.


JSON configuration
------------------

You can place virtual host definitions in `/etc/local/nginx/*.json`
that are managed by NixOS. They are built into the combined config file by
running fc-manage.

You may add other files to the directory, like SSL keys, as well.

The config snippets must contain a single JSON object that defines one or
more virtual hosts. Multiple JSON config files will be merged into one object.
It's a good idea to use one config file per virtual host.

This example.json defines a virtual host listening on all frontend IP addresses.
Requests to Port 80 are redirected to 443 which serves SSL using a managed
certificate from Let's Encrypt:

{ ... }:
{
  flyingcircus.services.nginx.virtualHosts = {
    "www.example.com"  = {
      serverAliases = ["a.example.com"];
      default =  true;
      forceSSL =  true;
    };
  };
}

```
{
  "www.example.org": {
    "serverAliases": ["example.org"],
    "default": true,
    "forceSSL": true,
    "root": "/srv/webroot",
    "extraConfig": "add_header Strict-Transport-Security max-age=31536000; rewrite ^/old_url /new_url redirect;",
    "locations": {
      "/cms": {
        "proxyPass": "http://localhost:8008"
      }
    }
  }
}
```

### Available Options

Options provided by NixOS are documented at
https://search.nixos.org/options?query=services.nginx.virtualHosts.&from=0&size=50&sort=relevance

We support the following custom options:
* `emailACME`: set the contact address for Let's Encrypt (certificate expiry, policy changes), defaults to none.
* `listenAddresses`: List of IPv4 and quoted IPv6 addresses

If `listenAddresses` is not set explicitly, all frontend IPs are used.

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

* `listenAddress`: Single IPv4 address
* `listenAddress6`: Single IPv6 address

`listenAddresses` should be used instead.

If only one of the listenAddress* options is given, the vhost listens only on IPv4 or IPv6.
If none of the `listenAddress*` options is given, all frontend IPs are used.
Using `listenAddresses` at the same time overrides the deprecated options.


### HTTPS and Let's Encrypt

For SSL support with redirection from HTTP to HTTPS, use `forceSSL`.
Let's Encrypt (`enableACME`) is activated automatically if one of `forceSSL`, `onlySSL` or `addSSL`
is set to true.
Self-signed certificates are created for new vhosts before Nginx starts or reloads.
They are replaced by the proper certificates after some seconds.
A systemd timer checks the age of the certificates and renews them automatically if needed.
To use a custom certificate, set the certificate options and set `"enableACME" = false`.

### SSL ciphers

With default settings, the following ciphers are available:

TLS 1.3:

TLS_AES_128_GCM_SHA256
TLS_AES_256_GCM_SHA384
TLS_CHACHA20_POLY1305_SHA256

TLS 1.2:

TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256

To use ciphers based on RSA for legacy clients, an RSA key must be
used for the certificates. Note that this disables the ciphers listed above
and reduces performance with newer clients.

Overriding the key type can be done per certificate:

security.acme.certs."test.fcio.net".keyType = "rsa2048";

Using two certificates to support both kinds of ciphers is possible with Nginx
but needs manual configuration.

For ciphers using DHE, an RSA certificate must be used. *dhparams* must be generated and set:

security.dhparams.params.nginx = {};
services.nginx.sslDhparam = config.security.dhparams.params.nginx.path;

This enables the following TLS 1.2 ciphers:

* TLS_DHE_RSA_WITH_AES_128_GCM_SHA256
* TLS_DHE_RSA_WITH_AES_256_GCM_SHA384

The DH param file is located at /var/lib/dhparams/nginx.pem.
This path can be referenced from Nix code by `security.dhparams.params.nginx.path` as shown in the config example above.

The services.nginx.sslCiphers option can be used to change the cipher list:

https://search.nixos.org/options&show=services.nginx.sslCiphers&from=0&size=50&sort=relevance&query=sslCiphers

If you enable weaker ciphers, you should also set services.nginx.legacyTlsSettings to true
and services.nginx.recommendedTlsSettings to false.

This sets `ssl_prefer_server_ciphers on` so better ciphers at the beginning of
the cipher list are used if possible.


Plain nginx configuration
-------------------------

You can use plain nginx config files at /etc/local/nginx/*.conf for configuration.
The contents are included verbatim into the combined config by running fc-manage.

You may add other files to the directory, like SSL keys, as well.

If you want to authenticate against the Flying Circus users with login permission,
use the following snippet, and *USE SSL*:

auth_basic "FCIO user";
auth_basic_user_file "/etc/local/htpasswd_fcio_users";

There is an `example-configuration` in this directory.
Copy to some file with the extension `.config` and adapt.

We recommend to use `listen ... default_server reuseport` like in the example
configuration for the default vhost.
The effect is that Nginx will start a separate socket listener for each worker.
This helps performance and also allows changing listen IPs on config reload
without the need to restart Nginx.

For ciphers using DHE, an RSA certificate must be used and dhparams must be set:

ssl_dhparam /var/lib/dhparams/nginx.pem;

The nginx.pem file is generated automatically on all VMs.
