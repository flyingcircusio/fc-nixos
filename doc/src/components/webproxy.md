# Vinyl Cache / Varnish (Webproxy) { #nixos-webproxy }

This role provides Vinyl Cache / Varnish Cache, the high-performance HTTP accelerator, in the latest version provided by NixOS, which is 9 at the moment. We also still support Varnish Cache 8, see below for more information about this.

## How we differ from what you are used to

Here is how we differ from what you already know from common Linux distributions
and how you are used to configure, start, stop and maintain these packages.

- **configuration file locations:**

  Since we use NixOS, configuration files have to be edited in
  `/etc/local/nixos`, followed by a NixOS rebuild which copies them into
  the Nix store and activates the new configuration. To do so, run the command
  `sudo fc-manage switch`.

- **service control:**

  We use `systemd` to control processes. You can use familiar commands
  like `sudo systemctl restart vinyld` to control services.
  However, remember that invoking `sudo fc-manage switch` is
  necessary to put configuration changes into effect. A simple restart is not
  sufficient. For further information, also see [nixos-local](../platform/fc-26.05-production/local.md#nixos-local).

### Role configuration


There are currently two ways to configure Vinyl Cache.
Please note that all configurations must be performed by a service user.

The recommended method is to use Nix. For an overview of the available configuration
options, look at the options in our search: [https://search.flyingcircus.io/search/options?q=flyingcircus.services.vinyl-cache&channel=fc-26.05-dev&page=1](https://search.flyingcircus.io/search/options?q=flyingcircus.services.vinyl-cache&channel=fc-26.05-dev&page=1).
As with all NixOS modules, place your configuration in an appropriately named file in the
`/etc/local/nixos` directory (e.g. `/etc/local/nixos/vinyl-cache.nix`).

Alternatively, you can also put your verbatim Vinyl Cache configuration into `/etc/local/vinyl-cache/default.vcl`.
This configuration is used as a fallback config, which means that it triggers
on all requests, if no more specific match was found in the configuration via Nix.

When you still have configuration in the `/etc/local/varnish/default.vcl` file,
this configuration will only be used as long as there is no nonempty
`/etc/local/vinyl-cache/default.vcl` file.

The role passes a handful of command line arguments to Vinyl Cache to
ensure reasonable default behaviour. If you wish to pass extra command
line arguments to the executable, then you should use the provided
`flyingcircus.services.vinyl-cache.extraCommandLine` NixOS
option. Arguments specified using this option (which may be defined
multiple times) will be merged into the list of arguments passed to
Vinyl Cache along with the role defaults.

### Use Varnish Cache 8

The migration from Varnish Cache 8 to Vinyl Cache 9 can cause problems for some setups.
To ease the migration to fc-nixos 26.05, we also support Varnish Cache 8 for this release.
This support will be removed in fc-nixos 26.11.

To use Varnish Cache 8, set the following NixOS option
```
flyingcircus.roles.webproxy.package = pkgs.varnish80;
```

Please configure Varnish Cache 8 using the `flyingcircus.services.varnish` NixOS module or the `/etc/local/varnish/default.vcl` file.

The `/etc/local/vinyl-cache/default.vcl` file has no effect if you didn't migrate to Vinyl Cache yet.

### Monitoring

- We monitor that the vinyld process is running.

- Please add a custom http checks which suite your needs to to `/etc/local/sensu-client`, for instance:

  ```
  {
    "vinyl-cache": {
      "command": "check_http -H localhost -p 8080",
      "notification" : "vinyl cache broken",
      "interval": 120,
      "standalone": true
    }
  }
  ```
