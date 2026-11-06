# 4. Calculate service memory limits from usable service memory

Date: 2026-11-11

## Status

Accepted

## Context

Our platform provides services like Percona, PostgreSQL, MariaDB, which all expose configuration options to define how
much memory they use. Depending on the service, this memory is allocated either at startup or dynamically later.

Currently, service memory limits are calculated using the minimum of the currently allocated VM memory and the configured
VM memory (which takes effect after a reboot).

We need to support scaling VM memory up and down.

Current downsides are: services that allocate all specified memory at startup can use more memory than is actually
usable by applications/services on the VM. Additionally, services get restarted outside of a maintenance window whenever
the configured memory is decreased.

## Decision

We will calculate memory limits for services in their configuration options based on the usable service memory
(total VM memory minus system overhead), as outlined in our public documentation.

The implementation depends on the characteristics of the service, in order of preference:

1. Calculate the service's memory limit based on a memory percentage NixOS role/service option during the systemd
   `ExecStartPre` phase or equivalent, if the systemd service or NixOS module allows this.

2. Calculate the service's memory limit in our platform using the `fclib.currentAvailableMemory` lambda function and
   write the service into the service configuration file.

Additionally, we will add an assertion at evaluation time to check that the specified percentage values do not exceed
100%, as doing so would overload the VM either immediately or during periods of high load.

For VMs that have less total memory than the defined overhead will not be used in service memory calculations.

## Consequences

During the upgrade to fc-nixos 26.11, which is the first version including this, any service memory percentages set to very low
values need to be adjusted upward.

Once, machines are upgraded to this version, it provides sensible defaults for services.
For example, it solves the issue of Percona 8.4 overloading the machine even when running as its only service.

Implementation option 1 partly goes against how NixOS thinks about service configuration files. In the context of
secret management, it is common to construct a runtime configuration file based on the templated one with the NixOS
module system to inject secrets. However, using structured config and generated configuration files is common for memory
configuration options. As this implementation is more deeply integrated with internals of the NixOS module of the service,
it is more likely to break and require changes from our side.y

Implementation option 2 does not solve the issue where decreasing the configured VM memory triggers an immediate service
restart outside of the maintenance window. With the resources currently available to us, this is unavoidable.
This may change in the future, when it is possible to build a NixOS system for a VM with the new memory options directly
before the reboot to apply the memory changes and boot in the adjusted NixOS system.
