# ADR 5 - Calculate service memory limits from usable service memory

Date: 2026-11-24
Status: Accepted

## Context

Our platform automatically provides application-specific memory limits for
services like Percona, PostgreSQL, MariaDB with the intention to allow them
to properly use the available system memory in a production-ready fashion.

Most of those services already provide configuration options for this. Some
services allocate their memory directly at startup, others will allocate it
over time when running and being actively used.

Before this ADR we took two values into account:

* "actual memory": the memory of the VM currently provided by the hypervisor
  and exhibited by the linux kernel in the `MemTotal` variable. This deviates
  from the physically available memory as the kernel dynamically subtracts
  overhead for the kernel itself, the BIOS,  etc.
* "configured memory": the amount of RAM configured in the directory database.

For allocation purposes we took the minimum of both values, to ensure services
do not accidentally fail to start when rebooting to update the actual memory
when the configured memory disagrees.

We generally need to continue to support changing VMs memory both up and down.
This is a hard problem, as VMs may crash or shutdown at any time and may reboot
with a different amount of memory than they were running at this point. This
may lead to services not getting restarted properly as they may overallocate
until the config has been updated.

After having investigated OOM situations in the last year, we made a
specification about what applications can expect of the VMs actual memory to
be usable for application purposes. Our recommendation can be quickly described
as considering 2.5 GiB of a VMs memory to not be application usable. The minimum
VM size of 3 GiB of memory thus allows roughly 0.5 GiB for application purposes.
This has not yet been integrated into the automated memory configurations.

The following downsides currently apply:

- applications may be configured with much higher memory limits than would
  be allowed by the current "2.5 Gib overhead" rule.

- applications may get restarted outside of maintenance windows because upon
  nixos rebuilds the minimum of actual and configured memory may suddenly
  change (e.g. a change in the directory parameter or a kernel tunable changing
  the amount of available memory)

Unexpected restarts are prohibitive in production environments.

All the automated config options for applications are only valid when run as
standalone services. VMs with multiple of those applications may end up
with >100% of application-available memory to be allocated.

## Decision

We will calculate memory limits for services in their configuration options
based on the "usable service memory" (total VM memory minus system overhead),
as outlined in our public documentation.

To avoid changes caused by dynamic kernel computations, we will base this on
the hypervisor memory instead of `MemTotal` (as an approximation using
MemTotal and rounding up to the next GiB is fine). The 2.5GiB overhead may be
exceeded on larger machines - we've seen MemTotal to be relative to the
overall size with roughly 1-2% and on VMs at 100GiB this itself can mean 2
GiB of overhead, so the overall overhead may grow to 3-4 GiB instead. We
think this will not be an urgent issue as VMs at that size tend to have more
wiggle room.

The implementation depends on the configuration facilities made available by
the specific service, in order of our preference:

1. service runtime config: calculate the service's memory limit based on a memory
   percentage given through a service-specific NixOS option during the systemd
   `ExecStartPre` phase or equivalent, if the service allows this.

2. nixos evaluation time: calculate the service's memory limit and write this directly
   into the appropriate config file.


We need to provide two implementations for computing the amount of memory: one
at runtime, the other while evaluating the nixos
configuration (`fclib.currentAvailableMemory`).

Additionally, we will add an assertion at evaluation time to check that the
specified percentage values do not exceed 100%, as doing so would overload
the VM either immediately or during periods of high load.

This approach will not be used if VMs have less total memory than the defined
overhead (2.5 GiB) but will fall back to the old implementation and will emit
a warning.

When implementing a new service that allows memory management, developers are
expected to:

1. provide an `enable` option
2. provide an option `memoryPercentage`
3. register with `nixos/platform/memory.nix` so that it participates
   in the protection against overcommitting memory.

## Consequences

During the upgrade to fc-nixos 26.11 any service memory percentages set to
very low values need to be adjusted upward. Use version switches to ensure
a smooth upgrade path.

Once machines are upgraded to this version, it provides sensible defaults for
services. For example, it solves the issue of Percona 8.4 overloading the
machine even when running as its only service. Previous customizations
should be reviewed whether they can be removed.

Two drawbacks of this soluation:

1. Runtime configuration of services goes against how NixOS thinks about service
   configuration files. In the context of secrets management, it is common to
   construct a runtime configuration file based on the templated one with the
   NixOS module system to inject secrets. However, using structured config and
   generated configuration files is common for memory configuration options. As
   this implementation is more deeply integrated with internals of the NixOS
   module of the service, it is more likely to break and require changes from
   our side at unfortunate moments.

2. Evaluation-time configuration does not solve the issue where decreasing the
   VM's configured memory will trigger an immediate service restart outside of
   a scheduled maintenance window. With the resources currently available to us,
   this is unavoidable. This may change in the future, when it is possible to
   build a NixOS system for a VM with the new memory options directly before
   the reboot to apply the memory changes and boot in the adjusted NixOS system.
