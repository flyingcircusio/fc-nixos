(nixos-opensearch)=

# OpenSearch

Managed instance of [OpenSearch](https://opensearch.org) in version 3.5.x.

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
    nodes = [ "example00" "example02" ];
    heapPercentage = 50;

    # Only for initialization of new multi-node clusters!
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
available RAM: _systemMemory _ heapPercentage / 100\*

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
- Upgrade the VM to 25.05 which also upgrades OpenSearch.

See the [22.11 OpenSearch role docs](https://doc.flyingcircus.io/roles/fc-22.11-production/opensearch.html#migrate-upgrade-from-elasticsearch) for the migration process.

We will provide Elasticsearch roles on 25.05 in the future to allow upgrading the VM first
while keeping the same ES versions. You can migrate to OpenSearch later.

## Monitoring

The following checks are provided by our opensearch service:

- Circuit breakers active
- Cluster health
- Heap too full
- Node status
- Shard allocation status

## Automated maintenance

When operating as a multi-node cluster, the automated maintenance
system ensures that at most one member of the cluster performs
maintenance at the same time. Additionally, before running maintenance
activities on hosts which are members of a multi-node cluster, the
cluster state must be green. The check will wait for up to 60 seconds
for the cluster to become green.

## Generate vector embeddings using FC AI

To support semantic search OpenSearch allows to generate and store vector
embeddings. This is mostly covered in the [official
documentation](https://docs.opensearch.org/latest/vector-search/getting-started/auto-generated-embeddings/).
Here we cover the specifics to connect OpenSearch to the FC AI.

For more informations about our AI API product, please visit
https://flyingcircus.io/en/ai and
https://doc.flyingcircus.io/platform/infrastructure/ai.html.

Preparing the cluster:

- Unlike some examples we are offloading the ML tasks to an external API instead
  of running them locally. To enable this, set
  [`plugins.ml_commons.only_run_on_ml_node`](https://docs.opensearch.org/latest/ml-commons-plugin/cluster-settings/#run-tasks-and-models-on-ml-nodes-only)
  to `false`.

- You need to enable the API endpoint via setting
  [`plugins.ml_commons.trusted_connector_endpoints_regex`](https://docs.opensearch.org/latest/ml-commons-plugin/remote-models/index/#adding-trusted-endpoints)
  to e.g. `^https://ai\\.rzob\\.fcio\\.net/.*$`.

- The ML response needs to be post-processed, see example below.

A complete example in Python might look like this:

```python
import time
from opensearchpy import OpenSearch, RequestError

AI_KEY = "your ai access key"
OS_HOST = "..."
OS_PORT = 9200

os = OpenSearch(
    hosts=[{"host": OS_HOST, "port": OS_PORT}],
    http_compress=True,  # enables gzip compression for request bodies
    use_ssl=False,
)


POST_PROCESS = """
    def json = "{\\"name\\": \\"sentence_embedding\\", \
         \\"data_type\\": \\"FLOAT32\\", \
         \\"shape\\": [" + params.data[0].embedding.length + "], \
         \\"data\\": " + params.data[0].embedding + "}";
    return json;
"""

os.cluster.put_settings(
    body={
        "persistent": {
            "plugins.ml_commons.only_run_on_ml_node": "false",
            "plugins.ml_commons.native_memory_threshold": "99",
            "plugins.ml_commons.trusted_connector_endpoints_regex": [
                "^https://ai\\.rzob\\.fcio\\.net/.*$",
            ],
        }
    }
)

# Model Group
response = os.plugins.ml.register_model_group(
    body={
        "name": "remote_fc_ai",
        "description": "A model group for external models hosted by FC",
    }
)
model_group = response["model_group_id"]
print("Model group", model_group)

response = os.plugins.ml.create_connector(
    body={
        "name": "embeddinggemma:300m connector",
        "description": "Connect to FC embeddinggemma:300m",
        "version": 1,
        "protocol": "http",
        "parameters": {
            "endpoint": "ai.rzob.fcio.net",
            "model": "embeddinggemma:300m",
        },
        "credential": {
            "openAI_key": AI_KEY,
        },
        "actions": [
            {
                "action_type": "predict",
                "method": "POST",
                "url": "https://${parameters.endpoint}/openai/v1/embeddings",
                "headers": {
                    "Authorization": "Bearer ${credential.openAI_key}"
                },
                "request_body": '{ "model": "${parameters.model}", "input": ${parameters.input} }',
                "post_process_function": POST_PROCESS,
            }
        ],
    }
)
connector_id = response["connector_id"]
print("Connector id", connector_id)

response = os.plugins.ml.register_model(
    body={
        "name": "embeddinggemma:300m",
        "function_name": "remote",
        "model_group_id": model_group,
        "description": "Embedding Model",
        "connector_id": connector_id,
    },
)

assert response["status"] == "CREATED"
task_id = response["task_id"]

state = None
while True:
    response = os.plugins.ml.get_task(task_id=task_id)
    state = response["state"]
    print(f"Waiting for model import, current state: {state}")
    if state == "COMPLETED":
        break
    time.sleep(1)
model_id = response["model_id"]
print("Model id:", model_id)

response = os.ingest.put_pipeline(
    id="document-ingest",
    body={
        "description": "Pipeline to ingest documents",
        "processors": [
            {
                "text_embedding": {
                    "model_id": model_id,
                    "field_map": {"body": "passage_embedding"},
                }
            }
        ],
    },
)
print(response)

response = os.indices.create(
    index=self.INDEX,
    body={
        "settings": {
            "index.knn": True,
            "index.number_of_shards": 2,
            "default_pipeline": "document-ingest",
        },
        "mappings": {
            "properties": {
                "docid": {"type": "keyword"},
                "passage_embedding": {
                    "type": "knn_vector",
                    "dimension": 768,  # Must match the ML output vector
                    "space_type": "l2",
                },
                "body": {"type": "text"},
                # Add more fields as required
            }
        },
    },
)
print(response)

```
