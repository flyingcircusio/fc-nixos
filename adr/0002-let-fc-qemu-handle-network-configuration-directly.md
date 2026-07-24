# 2. Let fc.qemu handle network configuration directly

Date: 2026-07-20

## Status

Accepted

## Context

Our network complexity is growing and the glue code between qemu, fc.qemu, and
fc-nixos is becoming unwieldy:

1. A chrooted qemu has a hard time calling the `downscript` and Qemu guidance
   also seems to lean towards: the scripts are only there for simple use cases -
   if you have an orchestrator then it should be the one setting interfaces up
   and also cleaning them up.

2. We have to pass-through information about what needs to happen by providing
   multiple shell-scripts for each type of interface and can only ever pass the
   interface name as an argumet. We then have to jump through additional hoops
   to map this back to the ENC config to e.g. determine network IDs, MAC
   addresses, etc. `fc-qemu` already has all that information readily available.

3. Keeping all the scripts in sync with the growing complexity becomes tangled
   an a hard sell.

Also, there is pre-existing vertical integration with Ceph, so this is not as
big a paradigm shift as it might seem.

## Decision

Let fc.qemu internally handle network configuration instead of using qemu
script/downscript parameters.

Remove the (now superfluous) network configuration enty points from
fc.qemu/fc-nixos.

## Consequences

This will reduce complexity and improve test coverage, but ties fc.qemu closer
to fc-nixos and thus may require touching fc.qemu more often when adjustments to
this code is needed.

Backwards compatibility will be kept by keeping fc.qemu starting VMs with the
`script` option for now, which will simply not exist (or be a noop) on host with
an appropriately new fc-nixos but will keep working as is on older hosts.
