(nixos-elasticsearch)=

# Elasticsearch

Managed instance of [Elasticsearch](https://www.elastic.co/elasticsearch).
There's a role for each supported major version, currently:

- elasticsearch6: 6.8.21
- elasticsearch7: 7.10.2

We use the free versions of Elasticsearch, which are published under the Apache
2.0 license. Client libraries may not work or need additional configuration if
they expect the unfree versions of Elasticsearch. Note that *x-pack* features
are not available in the free version.

Elastic doesn't provide updates to the 7.x line anymore so 7.10.2
will be the last available version.

:::{warning}
This is the last platform version that supports Elasticsearch.
Migrate to {ref}`nixos-opensearch` which is a fork of Elasticsearch
7.10.2.
:::

## Interaction

The Elasticsearch API is listening on the SRV interface. You can access
the API of nodes in the same project via HTTP without authentication.
Some examples:

Show active nodes:

```shell
curl test66:9200/_cat/nodes
```

Show cluster health:

```shell
curl test66:9200/_cat/health
```

Show indices:

```shell
curl test66:9200/_cat/indices
```

## Configuration

The role works without additional config for single-node setups.
By default, the cluster name is the host name of the machine.

Custom config can be set via NixOS options which is required for multi-node
setups. Plain config in {file}`/etc/local/elasticsearch` is still supported, too.
See {file}`/etc/local/elasticsearch/elasticsearch/elasticsearch.nix.example` for an example.
Copy the file to {file}`/etc/local/nixos/elasticsearch.nix`, for example, to
include it in the system config.

To see the final rendered config for Elasticsearch, use the
{command}`elasticsearch-show-config` command as service or sudo-srv user.

To activate config changes, run {command}`sudo fc-manage --build`
  (see {ref}`nixos-local` for details).

### NixOS Options

**flyingcircus.roles.elasticsearch.clusterName**

The cluster name ES will use. By default, the string from
{file}`/etc/local/elasticsearch/clusterName` is used. If the file doesn’t exist,
the host name is used as fallback. Because of this, you have to set the
cluster name explicitly if you want to set up a multi-node cluster.

**flyingcircus.roles.elasticsearch.heapPercentage**

Percentage of memory to use for ES heap. Defaults to 50 % of available
RAM: `systemMemory * heapPercentage / 100`

**flyingcircus.roles.elasticsearch.esNodes**

Names of the nodes that join this cluster and are eligible as masters.
By default, all ES nodes in a resource group are part of this cluster
and master-eligible. Note that all of them have to use the same
clusterName which must be set explicitly when you want to set up a
multi-node cluster.

If only one esNode is given here, the node will start in single-node
mode which means that it won’t try to find other ES nodes before
initializing the cluster.

Having both ES6 and ES7 nodes in a cluster is possible. This allows
rolling upgrades. Note that new nodes that are added to a cluster have
to use the newest version.

ES7: Values must use the same format as nodeName (just the hostname by
default) or cluster initialization will fail.

**flyingcircus.roles.elasticsearch.initialMasterNodes**

*(ES7 only, has no effect for ES6)*

Name of the nodes that should take a part in the initial master
election.

:::{warning}
This should only be set when initializing a cluster
with multiple nodes from scratch and removed after the cluster has
formed!
:::

By default, this is empty which means that the node will join an
existing cluster or run in single-node mode when esNodes has only one
entry. You can set this to
`config.flyingcircus.roles.elasticsearch.esNodes` to include all
automatically discovered nodes.

**flyingcircus.roles.elasticsearch.extraConfig**

Additional YAML lines which are appended to the main
{file}`elasticsearch.yml` config file.

### Legacy Custom Config

You can add a file named {file}`/etc/local/elasticsearch/clusterName`, with
the cluster name as its sole contents.

To add additional configuration options, create a file
{file}`/etc/local/elasticsearch/elasticsearch.yml`. Its contents will be
appended to the base configuration.

## Upgrades

Rolling upgrades for Elasticsearch 6 multi-node clusters to 7 are supported.
Nodes should be upgraded one at a time to ensure continous operation of the
cluster. Upgrading nodes is done by changing the role of the machine to
*elasticsearch7*.

### Upgrade/Migration to OpenSearch

Upgrading to OpenSearch is possible when starting from ES7. All indices must
have been (re-)indexed with ES7 before doing so. See
{ref}`nixos-opensearch` for the upgrade process.

## Monitoring

The following checks are provided by the elasticsearch roles:

- Circuit Breakers active
- Cluster Health
- File descriptors in use
- Heap too full
- Node status
- Shard allocation status
