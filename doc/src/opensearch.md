(nixos-opensearch)=

# OpenSearch

Managed instance of [OpenSearch](https://opensearch.org) in version 2.11.x.


## Interaction

Run `opensearch-readme` to show a dynamic README file which shows information
about the running OpenSearch config and role documentation.

The `opensearch-plugin` command can be run as `opensearch` user.
Changing to that user is allowed for service and sudo-srv users:

```shell
sudo -u opensearch bash
opensearch-plugin list
```

### API

The OpenSearch API is listening on the SRV interface. You can access
the API of nodes in the same project via HTTP without authentication.
Some examples:

Show active nodes:

```shell
curl example00:9200/_cat/nodes
```

Show cluster health:

```shell
curl example00:9200/_cat/health
```

Show indices:

```shell
curl example00:9200/_cat/indices
```

## Configuration

The role works without additional config for single-node setups.
By default, the cluster name is the host name of the machine.

Custom config can be set via NixOS options and is required for multi-node
setups.

Example:

```nix
{ config, pkgs, lib, ...}:
{
  flyingcircus.roles.opensearch = {
    clusterName = "example";
    nodes = [ "example00", "example02" ];
    heapPercentage = 50;

    #Only for initialization of new multi-node clusters!
    initialMasterNodes = [ "example00" ];
  };
  services.opensearch.settings = {
    "action.destructive_requires_name" = true;
  };
}

```

See `/etc/local/opensearch/opensearch.nix.example`.

Copy the content to `/etc/local/nixos/opensearch.nix` to include it in
the system config.

To activate config changes, run `sudo fc-manage switch`.

Run `opensearch-show-config` as `service` or `sudo-srv` user to see
the active configuration used by OpenSearch.

### Role NixOS Options

**flyingcircus.roles.opensearch.clusterName**

The cluster name OpenSearch will use. By default, the host name is
used. Because of this, you have to set the cluster name explicitly
if you want to set up a multi-node cluster.

**flyingcircus.roles.opensearch.nodes**

Names of the nodes that join this cluster and are eligible as masters.
By default, all OpenSearch nodes in a resource group are part of this cluster
and master-eligible.

Note that all of them have to use the same clusterName which must be
set explicitly when you want to set up a multi-node cluster.

If only one node is given here, the node will start in single-node
mode which means that it won't try to find other OpenSearch nodes before
initializing the cluster.

Values must use the same format as nodeName (just the hostname
by default) or cluster initialization will fail.

**flyingcircus.roles.opensearch.initialMasterNodes**

Name of the nodes that should take a part in the initial master election.
WARNING: This should only be set when initializing a cluster with multiple nodes
from scratch and removed after the cluster has formed!
By default, this is empty which means that the node will join an existing
cluster or run in single-node mode when nodes has only one entry.
You can set this to `config.flyingcircus.services.opensearch.nodes` to include
all nodes.

**flyingcircus.roles.opensearch.heapPercentage**

Percentage of memory to use for OpenSearch heap. Defaults to 50 % of
available RAM: *systemMemory * heapPercentage / 100*

### Upstream NixOS Options

**services.opensearch.settings**

Add arbitrary OpenSearch settings here. See
[OpenSearch/opensearch.yml](https://github.com/opensearch-project/OpenSearch/blob/main/distribution/src/config/opensearch.yml)
for an example config file.

OpenSearch settings are specified as flat key value pairs like
`"action.destructive_requires_name" = true`;

Note that the key must be quoted to stop Nix from interpreting the name
of the setting as a path to a nested attribute.


## Migrate from Elasticsearch

Currently, the last platform version providing Elasticsearch is 22.11.
The current upgrade path is:

- On 22.11, switch from Elasticsearch 6 to 7 and reindex.
- Migrate from Elasticsearch 7 to OpenSearch.
- Upgrade the VM to 23.11 which also upgrades OpenSearch.

See the [22.11 OpenSearch role docs](https://doc.flyingcircus.io/roles/fc-22.11-production/opensearch.html#migrate-upgrade-from-elasticsearch) for the migration process.

We will provide Elasticsearch roles on 23.11 in the future to allow upgrading the VM first
while keeping the same ES versions. You can migrate to OpenSearch later.

## Monitoring

The following checks are provided by our opensearch service:

- Circuit breakers active
- Cluster health
- Heap too full
- Node status
- Shard allocation status
