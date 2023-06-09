(nixos-opensearch)=

# OpenSearch

Managed instance of [OpenSearch](https://opensearch.org) which was originally
forked from Elasticsearch 7.10.2.


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


## Migrate/Upgrade from Elasticsearch


Upgrading to OpenSearch is possible when starting from ES7.

:::{warning}
All indices must have been indexed with ES7 before migrating or
starting OpenSearch will fail! See the
[Elasticsearch documentation](https://www.elastic.co/guide/en/elasticsearch/reference/7.10/reindex-upgrade-inplace.html)
for instructions.
:::

Start the migration by activating the `opensearch` role and deactivating the
`elasticsearch7` role at the same time, followed by a system rebuild with
{command}`fc-manage switch -be` or just waiting for the next run of the fc-agent service.

On OpenSearch startup, existing data from ES will be copied to the new data
directory at {file}`/var/lib/opensearch`. This will only happen when the
destination is empty to avoid overwriting existing OpenSearch data.

The process is usually very fast regardless of the amount of data as the
*reflink* feature of the XFS file system is used when copying the files. This
also saves disk space as files are only copied when they have to be
modified (*copy-on-write*).

The contents of the old data directory at {file}`/srv/elasticsearch` can
safely be removed after verifying that OpenSearch works as expected:

```shell
sudo -u opensearch rm -rf /srv/elasticsearch/*
```


## Monitoring

The following checks are provided by our opensearch service:

- Circuit breakers active
- Cluster health
- Heap too full
- Node status
- Shard allocation status
