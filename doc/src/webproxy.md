(nixos-webproxy)=

# Vinyl Cache / Varnish (Webproxy)

This role provides Vinyl Cache / Varnish Cache, the high-performance HTTP accelerator, in the latest version provided by NixOS, which is 9 at the moment. We also still support Varnish Cache 8, see below for more information about this.

## How we differ from what you are used to

Here is how we differ from what you already know from common Linux distributions
and how you are used to configure, start, stop and maintain these packages.

- **configuration file locations:**

  Since we use NixOS, configuration files have to be edited in
  {file}`/etc/local/nixos`, followed by a NixOS rebuild which copies them into
  the Nix store and activates the new configuration. To do so, run the command
  {command}`sudo fc-manage switch`.

- **service control:**

  We use {command}`systemd` to control processes. You can use familiar commands
  like {command}`sudo systemctl restart vinyld` to control services.
  However, remember that invoking {command}`sudo fc-manage switch` is
  necessary to put configuration changes into effect. A simple restart is not
  sufficient. For further information, also see {ref}`nixos-local`.

### Role configuration

There are currently two ways to configure Vinyl Cache.
Please note that all configurations must be performed by a service user.

For simple setups, you can put your verbatim Vinyl Cache configuration into {file}`/etc/local/vinyl-cache/default.vcl`.
If you still have configuration in {file}`/etc/local/varnish/default.vcl`,
it will only be used as long as there is no configuration in
{file}`/etc/local/vinyl-cache/default.vcl`.
Migrating your configuration to the new path is recommended.

The other option is to use our Vinyl Cache NixOS module. We recommended this approach
when your setup is more involved, e.g. when caching multiple domains on a single VM.
For an overview of the available configuration options, look at the options in our search: [https://search.flyingcircus.io/search/options?q=flyingcircus.services.vinyl-cache&channel=fc-26.05-dev&page=1](search.flyingcircus.io).
If you provide configuration via both {file}`/etc/local/vinyl-cache/default.vcl` and the NixOS module,
the configuration in {file}`default.vcl` will be used as a fallback when none of the configurations defined in the module
match on incoming requests.

As with all NixOS modules on our VMs, place your configuration in an appropriately named file in the directory
{file}`/etc/local/nixos` (e.g. {file}`/etc/local/nixos/vinyl-cache.nix`).

The role passes a handful of command line arguments to Vinyl Cache to
ensure reasonable default behaviour. If you wish to pass extra command
line arguments to the executable, you should use the provided
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

Please configure Varnish Cache 8 using the `flyingcircus.services.varnish` NixOS module or the {file}`/etc/local/varnish/default.vcl` file.

The `/etc/local/vinyl-cache/default.vcl` file has no effect if you didn't migrate to Vinyl Cache yet.

### Monitoring

- We monitor that the vinyld process is running.

- Please add a custom http checks which suite your needs to to {file}`/etc/local/sensu-client`, for instance:

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
