Nginx is enabled on this machine.

We provide basic config. You can use two ways to add custom configuration.

Changes to your custom config will cause nginx to reload without downtime on
the next fc-manage run if the config is valid. It will display a warning if
invalid settings are found in the nginx config.

Note that changes to listen directives that are incompatible with the running config
may require a manual Nginx restart that drops connections.
Using `reuseport` can avoid such situations (see below).

The combined nginx config file can be shown with: `nginx-show-config`

Structured configuration
------------------------

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

```
{
  "www.example.org": {
    "serverAliases": ["example.org"],
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
https://search.nixos.org/options?query=services.nginx.virtualHosts.&from=0&size=50&sort=relevance&channel=19.09

We support the following custom options:
* `emailACME`: set the contact address for Let's Encrypt, defaults to none.
* `listenAddress`: Single IPv4 address for vhost.
* `listenAddress6`: Single IPv6 address for vhost.

If only one of the listenAddress* options is given, the vhost listens only on IPv4 or IPv6.
If none of the `listenAddress*` options is given, all frontend IPs are used.

The `listen` option overrides our defaults: the `listenAddress*` options have
no effect and no IP is used automatically in this case.

One vhost definition should set the `default` option.
Otherwise, the first vhost entry will be the default one.
Because we combine config from multiple files, setting an explicit default is
strongly encouraged to avoid surprises with server name matching.

We also support a custom `reuseport` option for `listen` which is true by default.
The option only has an effect on the default vhost and is ignored on others.
The effect is that Nginx will start a separate socket listener for each worker.
This helps performance and also allows changing listen IPs on config reload
without the need to restart Nginx.


### HTTPS and Let's Encrypt

For SSL support with redirection from HTTP to HTTPS, use `forceSSL`.
Let's Encrypt (`enableACME`) is activated automatically if one of `forceSSL`, `onlySSL` or `addSSL`
is set to true.
Selfsigned certificates are created for new vhosts before Nginx starts or reloads.
They are replaced by the proper certificates after some seconds.
A systemd timer checks the age of the certificates and renews them automatically if needed.
To use a custom certificate, set the certificate options and set `"enableACME" = false`.


Manual configuration
--------------------

You can also use plain nginx config files /etc/local/nginx/*.conf for configuration.
The contents are included verbatim into the combined config by running fc-manage.

You may add other files to the directory, like SSL keys, as well.

If you want to authenticate against the Flying Circus users with login permission,
use the following snippet, and *USE SSL*:

auth_basic "FCIO user";
auth_basic_user_file "/etc/local/htpasswd_fcio_users";

There is also an `example-configuration` here. Copy to some file with the extension
.conf and adapt.

We recommend to use `listen ... default_server reuseport` like in the example
configuration for the default vhost.
The effect is that Nginx will start a separate socket listener for each worker.
This helps performance and also allows changing listen IPs on config reload
without the need to restart Nginx.

You can check if the config is valid with: `nginx-check-config`.
The script also warns about potential security issues with your config.
