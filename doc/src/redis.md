(nixos-redis)=

# Redis

This role installs the [Redis](https://redis.io) in-memory data structure store
in the latest version provided by NixOS which is 7.2.x at the moment.

## Components

- Redis

## Configuration

Out of the box, Redis is set up with a couple of common default
parameters and listens on the IP-addresses of the *loopback* (localhost) and
*ethsrv*-interfaces of your VM on port 6379 (See {ref}`networking`
for details on this topic).

In previous versions, custom redis configuration could be set
via {file}`/etc/local/redis/custom.conf` which is not supported anymore.

If you need to change the behaviour of Redis, you define your redis
configuration with the NixOS option
`services.redis.servers."".settings`. NixOS supports multiple
instances of Redis on a single host, so this option sets configuration
for the default instance with an empty instance name. See the NixOS
manual for further information.

Regarding setting the redis password, see the section on redis [passwords](#password).

The following NixOS module adds some modules to be loaded by Redis:

```nix
# /etc/local/nixos/redis.nix
{ ... }:
{
    services.redis.server."".settings = {
        loadmodule = [ "/path/to/my_module.so" "/path/to/other_module.so" ];
    };
}
```

See {ref}`nixos-custom-modules` for general information about writing custom NixOS
modules in {file}`/etc/local/nixos`.

There are also some options under `flyingcircus.services.redis`, namely
`maxmemory`, `maxmemory-policy`, `password` and `listenAddresses`.

The following NixOS module sets the listening addresses to `203.0.113.54` and
`203.0.113.57` as well as overriding the password to `foobarpass`. The maximum
memory size is set to `512mb`. The exact behavior Redis follows when the maxmemory
limit is reached is configured using the `maxmemory-policy` configuration directive
and is set to `noeviction` in this example. Read more at `redis topic lru cache <https://redis.io/topics/lru-cache>`.

```nix
# /etc/local/nixos/redis.nix
{ ... }:
{
    flyingcircus.services.redis = {
        listenAddresses = [ "203.0.113.54", "203.0.113.57 "];
        password = "foobarpass"; # Makes the password world readable, see paragraphs below for information
        maxmemory = "512mb";
        maxmemory-policy = "noeviction";
    };
}
```

As an alternative to setting the `maxmemory` by hand you can set a `memoryPercentage`
option. This will set the memory limit to a percentage of the total memory of the
system.

```nix
# /etc/local/nixos/redis.nix
{ ... }:
{
    flyingcircus.services.redis = {
        memoryPercentage = "50";
    };
}
```

For further information on how to activate changes on our NixOS-environment,
please consult {ref}`nixos-local`.

## Password

The authentication password is automatically generated upon installation
and can be read *and changed* by service users. It can be found in
{file}`/etc/local/redis/password`.

It can also be specified in the
`flyingcircus.services.redis.password` option where the password
will have a higher priority than the one in the filesystem. Setting
the `password` option makes the password world-readable to processes
on the VM since it will be stored in the nix store.

Overriding the `password` to `foobarpass` looks like this:

```nix
# /etc/local/nixos/redis.nix
{ ... }:
{
    flyingcircus.services.redis = {
        password = "foobarpass"; # Makes the password world readable
    };
}
```

## Interaction

Service users may invoke {command}`sudo fc-manage --build` to apply
service configuration changes and trigger service restarts (if necessary).

## Monitoring

The default monitoring setup checks that the Redis server is running
and is responding to [PING](https://redis.io/commands/ping).

% vim: set spell spelllang=en:
