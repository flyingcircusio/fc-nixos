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

% vim: set spell spelllang=en:
