(nixos-maintenance)=

# Automated Maintenance

VMs perform automated maintenance activities in announced maintenance windows.
Typical activities are system updates and reboots necessary to activate VM
property changes like memory size and the number of CPUs.

When new activities are scheduled by our central VM directory, a mail is sent
out to technical contacts with information about what's happening and when.

Activities can be merged into existing activities, updating them. For
significant changes, like additional service restarts, a mail is sent again
and the activity might get rescheduled to a later time. For small changes
and cancelled activities, no mail is being sent currently.

The `fc-agent` service executes due activities which happens every 10 minutes.
Some activities require a reboot which is done at the end of an agent run
after executing all activities.

Activities that are overdue (more than 30 minutes after planned time) are
postponed for at least 8 hours and scheduled again.

Before executing activities, the machine is put into *maintenance mode*
(it's *not in service*) to prevent triggering false alarms for expected
service interruptions during maintenance.

Maintenance is scheduled in a way so activities on different VMs shouldn't run
at the same time but this is not enforced by default. The execution of activities
can be delayed for various reasons so activities on different VMs may overlap.


## Additional Maintenance Constraints

To make sure that VMs don't execute activities at the same time, possibly affecting
availability of a redundant system, the NixOS option
`flyingcircus.agent.maintenanceConstraints.machinesInService` can be used.

This means that the specified machines from the same resource group have to
be *in service* (*not in maintenance mode*) when the machine tries to enter
maintenance mode. The constraint is checked shortly after entering
maintenance mode, before executing activities. If it's not met, due
activities are postponed to a later time and the machines leaves maintenance
mode immediately.

For the following example, assume that the VMs `example10`, `example11` and
`example12` are running redundant instances of an application and we want at
least two of the instances *in service* at any time.

This is enforced by this config, which has to be placed on each machine:
```nix
# /etc/local/nixos/maintenance_settings.nix
{ config, ... }:
{
  flyingcircus.agent.maintenanceConstraints.machinesInService = [
    "example10"
    "example11"
    "example12"
  ];
}
```

The name of the current machine is ignored, so the config can be the same on all machines.
