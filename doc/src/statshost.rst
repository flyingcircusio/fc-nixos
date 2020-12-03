.. _nixos2-statshost:

Statshost
=========

The Stathost role provides `Grafana <https://grafana.org>`_ dashboards for your project.
A variety of metrics are collected from your nodes using `Telegraf <https://www.influxdata.com/time-series-platform/telegraf/>`_, and are ingested into `Prometheus <https://prometheus.io>`_.

.. NOTE:: This is a stub. More documentation will follow.


Customization
-------------

A Telegraf daemon runs on all NixOS VMs. All metrics collected by Telegraf are picked up by Prometheus. You can add custom inputs by putting :file:`*.conf` files into :file:`/etc/local/telegraf`. Telegraf configuration files are in the `TOML <https://github.com/toml-lang/toml>`_ format. See the `Telegraf configuration page <https://github.com/influxdata/telegraf/blob/master/docs/CONFIGURATION.md>`_ for details. The available inputs are `documented separately <https://github.com/influxdata/telegraf/tree/master/plugins/inputs>`_.


To activate the configuration, run :command:`sudo fc-manage --build`. For further information, also see :ref:`nixos2-local`.
