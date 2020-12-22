.. _nixos-elasticsearch:

Elasticsearch
=============

Managed instance of `Elasticsearch <https://www.elastic.co/elasticsearch>`_.
There's a role for each supported major version, currently:

* elasticsearch5: 5.6.16 (not available on NixOS 20.09)
* elasticsearch6: 6.7.2 (20.09: 6.8.3)
* elasticsearch7: 7.8.0

We also provide :ref:`nixos-kibana` as a separate component.


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
