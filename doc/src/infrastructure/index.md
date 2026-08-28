---
global_sync_id: "v1"
---

% last review: 2026-08-24

% review schedule: 1 year

# Infrastructure

Most of the Flying Circus platform is deliberately invisible to your
virtual machines. This section documents the resources your VMs run on
and the infrastructure services around them.

- [Virtual machines](vms/index.md): how VMs run on Qemu/KVM, their
  resources, maintenance windows and deletion lifecycle.
- [Networking](networking/index.md): address allocation, connecting to
  VMs, firewall rules and the fallback router.
- [Storage](block-storage.md): persistent virtual disks on Ceph RBD.
- [Object storage](object-storage.md): S3-compatible object storage for
  large or shared data.
- [Backup](backup.md): automatic backups of your VMs and how restoration
  works.
- [Hardware](hardware/index.md): the servers and data centers the
  platform runs on.
