(nixos-statshost)=

# Statshost

The Stathost role provides [Grafana](https://grafana.org) dashboards for your project.
A variety of metrics are collected from your nodes using [Telegraf](https://www.influxdata.com/time-series-platform/telegraf/), and are ingested into [Prometheus](https://prometheus.io).

:::{NOTE}
This is a stub. More documentation will follow.
:::

## Customization

A Telegraf daemon runs on all NixOS VMs. All metrics collected by Telegraf are picked up by Prometheus. You can add custom inputs by putting {file}`*.conf` files into {file}`/etc/local/telegraf`. Telegraf configuration files are in the [TOML](https://github.com/toml-lang/toml) format. See the [Telegraf configuration page](https://github.com/influxdata/telegraf/blob/master/docs/CONFIGURATION.md) for details. The available inputs are [documented separately](https://github.com/influxdata/telegraf/tree/master/plugins/inputs).

To activate the configuration, run {command}`sudo fc-manage --build`. For further information, also see {ref}`nixos-local`.
