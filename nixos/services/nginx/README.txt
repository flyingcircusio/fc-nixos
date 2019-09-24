Nginx is enabled on this machine.

We provide basic config. You can use two ways to add custom configuration.

Changes to your custom config will cause nginx to reload without downtime on 
the next fc-manage run if the config is valid. It will display a warning if
invalid settings are found in the nginx config.

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

example.json containing a virtual with static root directory, a bit of
custom configuration, and SSL with a default certificate from Let's Encrypt:

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
https://nixos.org/nixos/options.html#services.nginx.virtualhosts.%3Cname%3E 

We support the following custom options:
* `emailACME`: set the contact address for Let's Encrypt, defaults to none.
* `listenAddress`: IPv4 address for vhost, defaults to `0.0.0.0`.
* `listenAddress6`: IPv6 address for vhost, defaults to `[::]`.

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
auth_basic_user_file "/etc/local/nginx/htpasswd_fcio_users";

There is also an `example-configuration` here. Copy to some file ending with
*.conf and adapt.

You can check if the config is valid with: `nginx-check-config`
