(nixos-slurm)=

# Slurm Workload Manager

:::{note}
Slurm support is in beta. Feel free to use it, but we suggest contacting
our support before putting anything into production.
:::

[Slurm](https://www.schedmd.com/) is an open source, fault-tolerant, and
highly scalable cluster management and job scheduling system. Slurm consists
of various services which are represented by separate Flying Circus roles
documented below.

The remainder of this documentation assumes that you are aware of the basics of
Slurm and understand the general terminology.

We provide version 23.2.0 of Slurm.

## Basic architecture and roles

:::{warning}
Keep in mind that Slurm is built to execute arbitrary commands on any Slurm node
with the permissions of the user starting the command on possibly another
machine. Keep sensitive data away from Slurm nodes and isolate Slurm as much as
possible, using a dedicated resource group without other applications.
:::

You can run one Slurm cluster per resource group. We generally recommend to
use separate clusters (and thus separate resource groups) for independent
projects. This will give you the most flexibility and will integrate
optimally into our platform aligning well on topics like access management,
monitoring, SLAs, maintenance, etc.

A resource group with Slurm roles can have additional machines which provide
additional services which may be needed to run jobs in Slurm. Such required
machines can also be included in the coordination of automated maintenance
as described later.

Machine authentication is handled by `munge`, using a shared secrets generated
by our central management directory. New worker nodes are automatically added
to existing clusters.


### slurm-controller

:::{note}
For new clusters, it's recommended to first set up a controller and add nodes
after that. The controller service will only start if there's at least one
node.
:::

:::{note}
For autoconfiguration, all slurm machines must have the same
amount of memory and CPU cores. If that's not the case, memory and CPU cores must
be set manually. See the {ref}`nixos-slurm-config-reference` on how to do that.
:::

This role runs {command}`slurmctld`. We add basic Cluster readiness monitoring
via Sensu and telemetry via Telegraf which can be ingested by a
{ref}`nixos-statshost` and displayed using a Grafana dashboard.

At the moment, we only support exactly one controller per cluster.

Maintenance of a machine with this role means that all worker nodes are
drained and set to `down` first. Maintenance activities only start when no jobs
are running anymore in the whole cluster.

After finishing a platform management task run (which happens every 10 minutes),
the controller sets all nodes to `ready` that have been set to `down` by an
automated maintenance if the nodes and all external dependency machines are not
in maintenance.


### slurm-dbdserver

:::{note}
At the moment, this role must run on the same machine as `slurm-controller`.
:::

Runs `slurmdbd` which is needed for job accounting. Automatically sets up a
{ref}`nixos-mysql` database with our platform defaults and
monitoring/telemetry.



### slurm-node

Runs `slurmd` which is responsible for processing jobs. There should be
multiple nodes in your cluster for production use but applying this role to a
machine which is also running the controller services is also supported for
testing purposes.

Nodes must be `ready` to accept jobs. The corresponding Slurm states are *IDLE*
when the node isn't processing jobs at the moment or *MIXED*/*ALLOCATED* if some
or all of its cores are in use at the moment, respectively.

Before running maintenance activities, the node is drained and stops accepting new
jobs. Nodes don't set themselves to `ready` after maintenance. Instead, the
controller activates nodes which are not in maintenance anymore after its own
platform management task run (every 10 minutes).

:::{warning}
Nodes that had an unexpected reboot or have been drained/downed manually
are not set to `ready` automatically by the platform management task. You
have to do that manually using one of the `ready` subcommands described in
{ref}`nixos-fc-slurm`.
:::

### slurm-external-dependency

This role does not provide any Slurm services but something that is needed to
run jobs via Slurm, for example a database accessed by job scripts. When such
machines go into maintenance, all nodes are drained first, like for a
controller maintenance. After the external dependency machine has finished
maintenance, the next run of the platform management task on the controller will set
the nodes to `ready`.

## Cluster interaction using Slurm commands

The usual Slurm commands are installed globally on every Slurm machine.

In general, all users can run slurm commands on all machines with a `slurm-*`
role. Some commands require the use of `sudo -u slurm` to run as slurm user.
This is allowed for(human) user accounts with the `sudo-srv` permission
without password.

Use `slurm-readme` to show dynamically-generated documentation specific for
this machine.



(nixos-fc-slurm)=
## Managing clusters with the fc-slurm command

Use {command}`fc-slurm` to manage the state of slurm compute nodes and display
status information about the cluster.

This command is also used by our platform management task before and after
maintenance, as well as to fetch telemetry data from Slurm and running monitoring
checks.

Some subcommands that modify state require `sudo`. This is allowed for
(human) user accounts with the `sudo-srv` permission without password.

The output and availability of subcommands depends on the role of the machine.


### Global Node Management

The `fc-slurm all-nodes` subcommand can be run on every machine with a *slurm*
role and operates on all nodes in the cluster.

Mark all nodes as `ready`:

```shell
sudo fc-slurm all-nodes ready
```

This is needed when nodes are out because they had an unexpected reboot or
have been drained/downed manually.


:::{note}
`all-nodes ready` skips nodes that are still in maintenance.
:::

You can specify a `reason` to restrict the affected nodes. Their reason
for being in a `down` state must contain the given string:

```shell
sudo fc-slurm all-nodes ready --reason-must-match "my node maintenance"
```


Drain all nodes (no new jobs allowed) and set them to `down` afterwards:

```shell
sudo fc-slurm all-nodes drain-and-down --reason "my global maintenance"
```

Dump node state info as JSON:

```shell
fc-slurm all-nodes state
```


### Single Node Management

Manage the state of nodes individually, by running `fc-slurm` directly on the node:

```shell
sudo fc-slurm drain-and-down --reason "my node maintenance"
sudo fc-slurm ready
```

Check the state of the node, also used by the `slurm` Sensu check:

```shell
fc-slurm check
```

### Controller Management

Controllers don't have management commands that affect their state at the
moment but you can run `fc-slurm all-nodes` on controller machines or look
at check output.

Check the state of the controller and all nodes, also used by the `slurm` Sensu check:

```shell
fc-slurm check
```


## Command Cheat sheet


Set all nodes to ready:

```shell
sudo fc-slurm all-nodes ready
```

View the dynamically-generated documentation for a machine:

```shell
slurm-readme
```
Show the current configuration:

```shell
slurm-show-configuration
```

Show running/pending jobs

```shell
squeue
```

Show partition state:

```shell
sinfo
```

Show node info:

```shell
sinfo -N
```

Show job accounting info:

```shell
sacct
```

## Known limitations

- For autoconfiguration, all nodes and the controller must have the same
  amount of memory and CPU cores. If that's not the case, memory and CPU must
  be set manually via Nix config to the same value on all Slurm machines
  because Slurm expects the config file to be the same everywhere.
- `slurm-dbdserver` and `slurm-controller` roles must be on the same machine.
- we support only one `slurm-controller` per cluster at the moment.



(nixos-slurm-config-reference)=

## Configuration reference

:::{warning}
Memory and CPU cores must be set to the same value on all Slurm machines
because Slurm expects the config file to be the same everywhere.

This also applies to machines that don't have the `slurm-node` role
even if the memory and CPU settings have no effect there.
:::

**flyingcircus.slurm.realMemory**

Memory in MiB used by a slurm compute node.

**flyingcircus.slurm.cpus**

Number of CPU cores used by a slurm compute node.

**flyingcircus.slurm.clusterName**

Name of the cluster. Defaults to the name of the resource group.

The cluster name is used in various places like state files or accounting
table names and should normally stay unchanged. Changing this requires
manual intervention in the state dir or slurmctld will not start anymore!

**flyingcircus.slurm.partitionName**

Name of the default partition which includes the machines defined via the `nodes` option.
Don't use `default` as partition name, it will fail!


**flyingcircus.slurm.accountingStorageEnforce**

This controls what level of association-based enforcement to impose on job
submissions. Valid options are any combination of associations, limits,
`nojobs`, `nosteps`, `qos`, `safe`, and `wckeys`, or all for all things
(except `nojobs` and `nosteps`, which must be requested as well). If
`limits`, `qos`, or `wckeys` are set, associations will automatically be
set.

By setting associations, no new job is allowed to run unless a
corresponding association exists in the system. If limits are
enforced, users can be limited by association to whatever job
size or run time limits are defined.

**flyingcircus.slurm.nodes**

Names of the nodes that are added to the automatically generated partition.
By default, all Slurm nodes in a resource group are part of the partition
called `partitionName`.

**services.slurm.extraConfig**

Extra configuration options that will be added verbatim at
the end of the slurm configuration file.

**services.slurm.dbdserver.extraConfig**

Extra configuration for `slurmdbd.conf` See also:
{manpage}`slurmdbd.conf(8)`.


### Example custom local config

```nix
{ ... }:

{
  flyingcircus.slurm = {
    accountingStorageEnforce = true;
    partitionName = "processing";
    realMemory = 62000;
    cpus = 16;
  };

  services.slurm.extraConfig = ''
    AccountingStorageEnforce=associations
  '';
}
```
