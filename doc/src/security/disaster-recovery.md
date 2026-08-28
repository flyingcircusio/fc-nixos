---
global_sync_id: "v1"
---

% last review: 2026-05-07

% review schedule: 1 year

% ISMSControl: A.17.1.2
% ISMSControl: A.5.29

% ISMSControl: A.11.1.4
% ISMSControl: A.7.5

# Disaster recovery { #disaster-recovery }

This disaster recovery plan provides an overview of potential disasters and how
the Flying Circus systems and personnel are prepared to deal with them.

For each scenario we give:

- a preventive action
- the recovery action
- the recovery time and recovery point objective
- measures we take to prevent the scenario

## Terminology

RTO

: Recovery time objective – the maximum time it takes to restore a service after
  discovering a disaster.

RPO

: Recovery point objective - the maximum age of data that will be made available
  after recovery from a disaster. Given as "time before the disaster".

!!! note
    If recovery actions are neither self-service nor automatic then a 1 hour
    response time is included to notify the standby support technician.

## Hardware errors

### Loss of active network component

Disaster prevention

: We deploy hot-standby routers and active-active redundant switch infrastructure. Selected networks that aren't part of our main platform may run on switches with warm-standby redundancy.

Disaster recovery

: Swap faulty component with standby component. This happens automatically
  for routers and for active-active redundant switches.

  Depending on the affected services higher level components' redundancies (
  storage, virtualisation) may allow faster recovery times.

  RTO for hot-standby routers: less than 15 seconds

  RTO for active-active redundant switch failures: less than 15 seconds

  RTO for warm standby redundant switch failures: 8 hours

  RPO: n/a

### Loss of VM server

Disaster prevention

: We buy professional hardware. We use redundant power supplies. OS disks are not
  made redundant - failure does not impact VM operations and affected hosts
  will be evacuated if needed.

Disaster recovery

: Migrate or restart virtual machines from the failed host on spare hosts.

  RTO: within customer-specific SLA + 15 minutes

  RPO: 0

### Loss of storage servers covered by redundancy

Disaster prevention

: We store all virtual machine images and object storage data on a distributed
  storage system (Ceph) with at least n+2 redundancy. Loss of individual disks
  and servers can be masked transparently.

  We can loose multiple storage servers, depending on the capacity of our
  cluster. We expect to be able to loose at least 2 servers in total without
  impacting service or data availability. A simultaneous failure of 2 servers
  may cause intermittent service outages while recovering to an n+1 redundancy
  state.

Disaster recovery

: Ceph performs automatic recovery. Reduced I/O performance may be experienced
  during this period on virtual machines.

  RTO: 5 minutes

  RPO: 0

### Loss of storage servers exceeding redundancy

Disaster prevention

: This is a multi-layered issue. In the case of loss of redundancy beyond
  automatic repair abilities requires manual specific diagnostics and
  decision-making.

  Customers wanting to exceed this may choose to keep an offsite backup as well
  as an emergemency operations setup with our secondary data center.

Disaster recovery

: Restore virtual machines from backup.

  RTO: 4 hours + 5 hours per TiB of VM storage

  RPO: 24 hours / 1 hour [^fn1]

### Loss of server rack

Disaster prevention

: The most likely scenario to loose a server rack is due to overheating and
  fire. We thus pack racks loosely to allow for optimal air-flow and density
  without over-heating. Also, the data center operator employs a smoke
  detection system that allows for early detection and fire prevention.

  Customers wanting to exceed this may choose to keep an offsite-backup as well
  as an emergemency operations setup with our secondary data center.

Disaster recovery

: Buy and install new hardware, provision to new rack in data center.

  RTO: 2-4 weeks

  RPO: not available

## Force majeure

### Loss of power in the data center

% ISMSControl: 7.5

Disaster prevention

: High SLA requirements from the data center. Regular personal inspections and
  interviews. Require redundant power lines, UPS backup, and diesel generators
  in the data center.

  Customers wanting to exceed this may choose to keep an offsite-backup as well
  as an emergemency operations setup with our secondary data center.

Disaster recovery

: Data center personnel restores power.

  RTO: n/a, covered by 3rd party 99.99% SLA

  RPO: n/a

### Loss of uplink connectivity in the data center

Disaster prevention

: The data center provides redundant uplinks to the internet together with
  separate underground cables from different directions. The data center
  also uses highly available routers and network infrastructure.

  The Flying Circus has a service level agreement on the availability of the
  network with the data center provider.

  Customers wanting to exceed this may choose to keep an offsite-backup as well
  as an advanced backup operations setup with our secondary data center.

Disaster recovery

: Data center restores connectivity

  RTO: n/a, covered by 3rd party 99.99% SLA

  RPO: n/a

### Loss of data center

Disaster prevention

: Our data center implements a variety of security measures certified through
  the ISO 27000 family.

  RZOB: <http://www.kamp.de/kamp-rechenzentrum/sicherheit.html>

Disaster recovery

: Evaluate recovery of data center, if possible together with the data
  center operator.

  Alternatively find new data center and rebuild infrastructure.

  Customers wanting to exceed this may choose to keep an offsite-backup as well
  as an emergemency operations setup with our secondary data center.

  RTO: n/a (24h for backup data center operations)

  RPO: n/a (depending on backup frequency)

## Software errors

### Filesystem corruption

Disaster prevention

: We use mature file systems in our storage cluster, backup solutions, and
  in the VM disks to avoid inconsistencies under failure scenarios.

Disaster recovery

: Restore filesystem or missing files from backups, recreate backups in case
  of file system errors on backup systems.

  RTO: depends on SLA [^fn2] and may require customer interaction to validate the restored data

  RPO: 1 day/1 hour [^fn1]

### Configuration errors

Disaster prevention

: Leverage automated, repeatable, and version-controlled configuration systems.

Disaster recovery

: Roll back configuration changes and restore backups if data is lost.

  RTO: depends on SLA [^fn2]

  RPO for reversible configuration changes: 4 hours

  RPO for restore: 1 day/1 hour [^fn1]

### Application errors

Disaster prevention

: Leverage automated, repeatable, and version-controlled application
  deployment. Leverage fully separated test/staging/production environments.

Disaster recovery

: Re-install application and restore backups if data is lost.

  RTO: depends on SLA [^fn2]

  RPO for reinstallation: 4 hours

  RPO for restore: 1 day/1 hour [^fn1]

## User errors

### Accidental single file deletion

Disaster prevention

: Performing backups. Customers may choose to increase the standard schedule (once every 24 hours) to a more frequent schedule (hourly).

Disaster recovery

: Restore deleted file from backup.

  RTO: depends on SLA [^fn2]

  RPO: 1 day/1 hour [^fn1]

### Accidental database/directory tree deletion

Disaster prevention

: Restricting root access and performing backups.

Disaster recovery

: Restore deleted files from backup.

  RTO: depends on SLA [^fn2]

  RPO: 1 day/1 hour [^fn1]

[^fn1]: RPO is 1 day for all virtual machines covered by the default backup
    schedule. Customers can opt for a more frequent backup schedule with hourly
    backups.

[^fn2]: Standard support reaction time is 4 hours during office hours.
    Customers may book SLAs with shorter guaranteed reaction times.
    Restore RTOs require the SLAs basic RTO + 5 hours per TiB of VM storage.
