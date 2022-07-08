.. _nixos-elasticsearch:

Elasticsearch
=============

Managed instance of `Elasticsearch <https://www.elastic.co/elasticsearch>`_.
There's a role for each supported major version, currently:

* elasticsearch6: 6.8.3
* elasticsearch7: 7.10.2

We also provide :ref:`nixos-kibana` as a separate component.

We use the free versions of Elasticsearch, which are published under the Apache
2.0 license. Client libraries may not work or need additional configuration if
they expect the unfree versions of Elasticsearch. Note that *x-pack* features
are not available in the free version.

Elastic doesn't provide updates to the 7.x line anymore so 7.10.2
will be the last available version. We are planning to move to OpenSearch
instead which is a fork of Elasticsearch 7.10.2.

Configuration
-------------

Upon activating the role, Elasticsearch forms a cluster with the same name as the VM.
To change the cluster name, add a file :file:`/etc/local/elasticsearch/clusterName`,
with the cluster name as its sole contents.
To activate run :command:`sudo fc-manage --build` (see :ref:`nixos-local` for details).

Elasticsearch instances are configured with a reasonable memory configuration,
depending on the VMs configured memory.

To add additional configuration options, add a file :file:`/etc/local/elasticsearch/elasticsearch.yml`.
Its contents will be appended to the base configuration.


Monitoring
----------

The following checks are provided by the elasticsearch role:

* Circuit Breakers active
* Cluster Health
* File descriptors in use
* Heap too full
* Node status
* Shard allocation status
