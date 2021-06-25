.. _nixos-kibana:

Kibana
======

`Kibana <https://www.elastic.co/kibana>`_ is a data analysis tool based on Elasticsearch.
There's a role for each supported major version, currently:

* kibana6: 6.8.3
* kibana7: 7.8.0

We provide :ref:`nixos-elasticsearch` as a separate component.
You need at least one VM with an Elasticsearch role matching the version of the Kibana role.
Both can be activated on the same VM which is the easiest way to run Kibana.


Configuration
-------------

Then Elasticsearch node Kibana connects to can be set by putting the URL
in a file :file:`/etc/local/kibana/elasticSearchUrl`.

If no URL has been set and Elasticsearch is running on the same machine,
the local node is used automatically.

To activate changes to the URL run :command:`sudo fc-manage --build`
(see :ref:`nixos-local` for details).

Features
--------

The reporting feature does not work on our platform.
We may add support for this in the future.
