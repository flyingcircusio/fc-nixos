---
global_sync_id: "v1"
---

# How to set up a LAMP stack

The Flying Circus platform provides components which can be used to set up an environment for operating PHP applications. The configuration *can* be automated with deployment tools of course, but this is not part of this tutorial.

What you should know before starting:

- The general ideas of the Flying Circus platform: [firststeps](../../infrastructure/getting-started/index.md#firststeps).
- The difference between human users and service users: [useraccounts](../users/index.md#useraccounts)
- How to connect to VMs via SSH (or SFTP): [connecting](../../infrastructure/networking/connecting.md#connecting)

Assumptions:

- There is only *one* VM, `myvm00`. The setup generally works in multi VM setups, too, though.
- You will host multiple sites in one setup.
- Each site is being hosted in a different service user. We use `s-myserviceuser` here. Switch to the service user with `sudo -iu s-myserviceuser`. The docroot is *inside* the service user's home directory.

## General structure

The general request flow for our LAMP stack is as follows:

- NGINX: SSL termination and domain/vhost specific configuration
- Apache: Used so `.htaccess` files work.
- PHP-FPM for actually running PHP code

In addition you likely want a variant of MySQL.

## Component setup

### MySQL

Enable a MySQL role of your choice, e.g. mysql57, percona80, in the VM dashboard on <https://my.flyingcircus.io/>. See the `nixos-mysql` role documentation for details.

If you just enabled a MySQL role it might not be available on the VM, yet. Call `sudo fc-manage -eb` to force a build. The `-e` option is there to reload the configuration you have set in the VM dashboard, so it's usually omitted when applying local changes.

To create a service-specific MySQL user and database you switch to the mysql user and start a mysql shell:

```Shell
$ sudo -iu mysql
mysql$ mysql

mysql> CREATE DATABASE myservice;
mysql> CREATE USER myservice@'%' IDENTIFIED BY 'a password';
mysql> GRANT ALL on myservice.* TO myservice@'%';
```

You will of course need a real username and password for your application.

Note that we used `myservice@'%'` as user name. This generally allows access from everywhere (`%`). Our firewall rules make sure that MySQL is only reachable via the SRV interface and only from other VMs in the *same* resource group. See [firewall](../../infrastructure/networking/firewall.md#firewall) for details.

### Apache / FPM

You configure Apache and FPM in one step. With the Flying Circus `lamp` role you define an Apache docroot which is properly hooked up with FPM.

But first, there are some generic Apache settings, which are used for *all* sites. :

```Nix
# /etc/local/nixos/apache.nix
{ pkgs, ... }:

{

  flyingcircus.roles.lamp = {

    # Configure PHP version:
    php = pkgs.lamp_php74;

    # Additional Apache configuration
    apache_conf = ''
      # ...
    '';

    # php.ini settings:
    php_ini = ''
      ; max filesize
      upload_max_filesize = 200M
      post_max_size = 200M


      date.timezone = Europe/Berlin

      ; Putting sessions in redis is a good idea.
      ; session.save_handler = redis
      ; session.save_path = "tcp://myvm00.fcio.net:6379?auth=<secret>"
    '';

  };
}
```

Now configure a docroot. It is best to create a separate service user for each project and separate the vhost configuration defining listening port and the corresponding docroot:

```Nix
# /etc/local/nixos/myservice.nix
{ config, ... }:
let
  # Define a variable for the port, so we don't need to keep it in sync
  # by ourselves.
  port = 8000;
in
{
  flyingcircus.roles.lamp = {
    hosts = [
      { port = port;
        docroot = "/srv/s-myserviceuser/application.git/docroot";
      }
    ];
  };
}
```

This setting configures both Apache *and* FPM automatically. To enable the configuration, call `sudo fc-manage -b`

The detailed documentation for this component is: `nixos-lamp`.

### NGINX

The NGINX component manages SSL termination and routing to Apache.

```nix
# /etc/local/nixos/myservice.nix, continued.
{ config, ... }:
let
  # ...
in
{
  flyingcircus.roles.lamp = {
    # ...
  };

  flyingcircus.services.nginx.virtualHosts = {
    "www.example.com"  = {
      serverAliases = [ "example.com" ];
      forceSSL = true;  # Create redirect from http to https
      enableACME = true;  # Create Let's Encrypt certificate
      extraConfig = ''
        # Additional verbatim NGINX config.
        add_header Strict-Transport-Security max-age=31536000;
      '';
      locations = {
        "/" = {
          # Pass request to Apache.
          proxyPass = "http://${config.networking.fqdn}:${port}";
          extraConfig = ''
            # Additional verbatim NGINX config.
          '';
        };
      };
    };
  };
}
```

You will find more details on NGINX configuration in the role documentation for `nixos-webgateway`.
