Nginx is enabled on this machine.

Manual configuration
--------------------

Put your site configuration into this directory as `*.conf`. You may
add other files, like SSL keys, as well.

If you want to authenticate against the Flying Circus users with login permission,
use the following snippet, and *USE SSL*:

auth_basic "FCIO user";
auth_basic_user_file "/etc/local/nginx/htpasswd_fcio_users";

There is also an `example-configuration` here. Copy to some file ending with
*.conf and adapt.

Structured configuration
------------------------

Alternatively, you can place virtual host definition in
`/etc/local/nginx/vhosts.json` which resembles NixOS nginx virtualHosts options

Example vhosts.json containing a virtual with static root directory, a bit of
custom configuration, and Let's encrypt SSL:

```
{
  "www.example.org": {
    "serverAliases": ["example.org"],
    "acmeEmail"
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

All options are documented in
https://nixos.org/nixos/options.html#services.nginx.virtualhosts. Note that an
non-standard attribute "acmeEmail" must be set to a contact mail address
in order to activate Let's encrypt.
