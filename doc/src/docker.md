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

Older versions of docker (NixOS 15.09) used the `devicemapper` storage driver which has been deprecated for some time. It will be removed in a future version of Docker.

On 23.11, docker refuses to start if it detects `devicemapper` and is not explicitly configured to use it. You can still choose to continue using `devicemapper` or migrate to `overlay2`.

To find out which storage driver Docker is using, run as service user:

```shell
docker info | grep Storage
```

Docker also logs warnings to the journal on startup if it is using `devicemapper`.

### Continue using devicemapper

Add {ref}`custom NixOS config <nixos-local>` like:

```nix
# /etc/local/nixos/docker.nix
{ ... }:
{
  virtualisation.docker.daemon.settings = {
    storage-driver = "devicemapper";
  };
}
```

Rebuild the system with `sudo fc-manage switch`.

### Switch to overlay2

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

You can remove the config after a successful migration.


% vim: set spell spelllang=en:
