(nixos-docker)=

# Docker

Runs a [Docker](http://docker.com) daemon to use containers for application
deployment.

## Interaction

All service users can interact with Docker using the {command}`docker` command.

## Network

The Flying Circus network is designed to allow customer application components
to talk to each other securely and reliably. We recommend using the `bridged`
networking option.

Programs running in a `bridged` container can access the rest of the network
similar to programs run directly on the host. They can access neighbouring
`srv` services in the same resource group and talk to the internet either
directly through the frontend network or masqueraded through the
server-to-server network.

:::{note}
We used to recommend the `host` networking option as a workaround due to
incompatibilities with the NixOS firewall management. This option is now no
longer recommended as it breaks fundamental assumptions about how containers
work and how they are isolated.
:::


(nixos-docker-storage-driver)=

## Docker Storage Driver

The storage driver is used for images and containers.

Currently, docker is using the `overlay2` storage driver for new installations.

For existing installations, Docker auto-detects the storage driver if not configured explicitly.

### Migrating from `devicemapper` to `overlay2`

Older versions of docker (NixOS 15.09) used the `devicemapper` storage driver.
If your docker setup is still using that storage driver, you need to migrate the storage
before updating to the NixOS 24.11 platform. The platform default for docker is
now docker-27, which does not support the `devicemapper` storage driver anymore.

To find out which storage driver Docker is using, run as service user:

```shell
docker info | grep Storage
```

On the NixOS 24.05 platform, docker also logs warnings to the journal on startup if it is using `devicemapper`.

:::{warning}
It's not possible to use another storage driver without downtime. You have to re-create images and containers!
:::

Changing the storage driver will render existing containers and images inaccessible.
Volumes are not affected by the storage driver change.

Old containers and images will still be kept in {file}`/var/lib/docker` and consume disk space. There's no supported way to remove them from disk after the change.

Because of that, clean up unneeded images and containers before switching, using `docker rmi` and `docker rm`. If it's OK to have more downtime and you are sure that you don't want to switch back, you can just remove all images and containers.

When you are ready to switch, add the following {ref}`custom NixOS config <nixos-local>` or change the existing config:

```nix
# /etc/local/nixos/docker.nix
{ ... }:
{
  virtualisation.docker.daemon.settings = {
    storage-driver = "overlay2";
  };
}
```

Rebuild the system with `sudo fc-manage switch` and re-create containers after that.

You are now ready to update your system to the NixOS 24.11 platform.
The config may be removed after a successful migration.


% vim: set spell spelllang=en:
