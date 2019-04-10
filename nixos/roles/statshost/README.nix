hostName:
''
Inter-project metrics
=====================

A node with the `statshost-master` role can aggregate metrics from several other
resource groups (projects). Each other RG must have one VM with with
`statshost-relay` role.


Statshost master
----------------

List each relay in `/etc/local/statshost/relays.json`. See the example file for
the expected format.


Statshost relays
----------------

Create firewall rules for the masters' SRV addresses in
`/etc/local/firewall/relay_prometheus` on each relay::

    ip46tables -I nixos-fw -s ${hostName}.fcio.net -p tcp --dport 9090 -j nixos-fw-accept


Prometheus metric relabelling
=============================

Custom relabel rules can be put into:

* `/etc/local/statshost/metric-relabel.yaml` for *all* jobs, and into
* `/etc/local/statshost/metric-relabel.<jobname>.yaml` for only a specific job.

See
<https://prometheus.io/docs/prometheus/latest/configuration/configuration/#relabel_config>
for documentation.
''
