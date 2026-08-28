---
global_sync_id: "v1"
---

% last review: 2025-11-06

% review schedule: 1 year

% ISMSControl: A.5.1.1
% ISMSControl: A.12.3.1
% ISMSControl: 8.13

# Backup { #backup }

All persistent data of a virtual machine is stored on a central storage
cluster. The storage cluster is independent of the host that runs the virtual
machine. The storage cluster keeps the virtual disk in Ceph RADOS Block Devices.

We perform backups at the "block layer": the virtual disk is copied as a
full image into our backup system, where either the filesystem can be mounted
read-only to retrieve individual files or the whole virtual disk can be
restored into Ceph.

The application software used for backups is [Backy], an open-source
backup solution.

S3 data is *not* backed up automatically.

All backup storage data is transparently encrypted before being stored onto
physical disks, see [data-at-rest-encryption](../security/data-protection.md#data-at-rest-encryption) for details.

## Schedule

Backups are run daily or hourly, depending on the chosen backup level.

The `default` (daily) backup schedule retains the following backups:

- Daily backups for the past 10 days.
- Weekly backups for the past 5 weeks.
- Monthly backups for the past 4 months.

The `frequent` (hourly) backup schedule retains the following backups:

- Hourly backups for the last 25 hours
- Daily backups for the past 10 days.
- Weekly backups for the past 5 weeks.
- Monthly backups for the past 4 months.

The the `longterm` backup schedule retains the following backups:

- Daily backups for the past 30 days.
- Monthly backups for the last 12 months.

The `frequent+longterm` backup schedule retains the following backups:

- Hourly backups for the last 25 hours
- Daily backups for the past 30 days.
- Monthly backups for the past 12 months.

If backups were missed then the retention period keeps at least that many
copies before deleting them, i.e. there will always be 25 hourly backups even
if a backup was missed for some reason.

Backups are created at fixed intervals but the time during the interval is not
guaranteed. I.e. daily backups for a specific VM occur every 24 hours at the
same time but there is no guarantee for a specific time, like 03:00.

Backups are *only* stored on-site. Off-site replication is available, please contact our [support](https://my.flyingcircus.io/support/).

## Procedure

Backups are performed outside of the virtual machine: the backup server
directly accesses the Ceph cluster to retrieve the data.

First the VM's filesystem is being frozen to ensure consistency of the backup.
Then a snapshot of the volume is made. The snapshot is then retrieved by the
backup server as a difference to the previous backup. After the backup is finished a random sample is verified against the snapshot, to further ensure consistency.

The backup procedure is logged to the filesystem of the backup server. We automatically monitor that all backups are taken within the agreed schedule.

## Restore

Single files or full VMs can be restored by our infrastructure administrators.
Please submit a support request with the following information:

- which machine to restore files for
- which files (specific path names)
- from which approximate time (e.g. "before last saturday")

[backy]: http://pythonhosted.org/backy/
