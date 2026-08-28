---
global_sync_id: "v1"
---

<a id="infrastructure-storage"></a>

# Virtual Disks / Block Storage { #infrastructure-storage-block }

VM storage is provided by a Ceph cluster as virtual disks / block devices.
The data in the cluster is transparently encrypted before being stored onto
physical disks, see [data-at-rest-encryption](../security/data-protection.md#data-at-rest-encryption) for details.

Each virtual disk is visible in VMs as `/dev/vda` and reflects an
underlying Ceph [RBD volume][rbd volume].

## Disk Layout { #infrastructure-storage-disk-layout }

VMs are fitted with 3 different virtual disks:

`/dev/vda`

: This disk contains an XFS partition and is mounted to the VFS root(`/`) and
  has the nominal size as requested in the VM configuration. The minimum size
  is 30 GiB and it contains the operating system as well as your application
  and user data.

  Depending on the installed software you may need to reserve between 5-15 GiB
  of this disk for the operating system. Our use of NixOS has a higher
  footprint here than other OSes as we support atomic updates and may need to
  keep up to 4 copies of the OS environment in this store at some points in
  time.

`/dev/vdb`

: This disk contains swap. It is sized depending on your machine's memory and 
  is at least 1 GiB or 32 times the square root of your VMs memory.

  Swap is only provided to allow the VM some wiggle room if it runs out of
  memory in critical situations and allows for some room to interact and
  diagnose VMs that are running low on memory. Our VM configuration prefers to
  not use swap as much as possible as it impacts performance quite badly. 

  | VM memory | Swap size |
  |---|---|
  | 1 GiB | 1 GiB |
  | 2 GiB | 1.4 GiB |
  | 4 GiB | 2 GiB |
  | 8 GiB | 2.8 GiB |
  | 16 GiB | 4 GiB |
  | 32 GiB | 5.7 GiB |
  | 64 GiB | 8 GiB |

`/dev/vdc`

: contains an XFS partition used as a bounded `/tmp` filesystem. Some
  applications (like MySQl) exercise their use of /tmp based on available space
  of this partition and - if mounted to `/` - can cause the disk to fill up and
  cause issues for other applications.

  If your application needs a larger or more specific amount of temporary
  space, create a separate directory in your deployment and point your
  application to it by setting the `TMPDIR` environment variable (or use
  application specific configuration to adjust this).

  This disk is sized depending on your root disk: it is at least 5 GiB or
  the square root of your root disk.

  | VM root disk | /tmp size |
  |---|---|
  | 10 GiB | 5 GiB |
  | 50 GiB | 7 GiB |
  | 100 GiB | 10 GiB |
  | 250 GiB | 15 GiB |
  | 500 GiB | 22 GiB |

## Storage Performance { #infrastructure-storage-performance }

We provide multiple storage pools with different performance characteristics, named **HDD** and **SSD** as an indicator of the expected performance:

|                 | HDD         | SSD        |
|:----------------|:-----------:|:----------:|
| IOPS (regular)  |         250 |      10000 |
| IOPS burst rate | 10× for 60s | 2× for 60s |
| bandwidth       |   250 MiB/s |  500 MiB/s |

The IOPS limit is accounted and enforced separately for *read* and *write* operations.  \
The bursting limits are calculated through the Qemu [*leaky bucket*][qemu-throttling] mechanism and thus can extend the burst period for burst rates smaller than the maximum.

[qemu-throttling]: https://github.com/qemu/qemu/blob/3656e761bcdd207b7759cdcd608212d2a6f9c12d/docs/throttle.txt

## Migrating disks between storage pools { #infrastructure-storage-pool-migration }

VM disks can be migrated between those pools by selecting a new pool. The VM
will detect the change and schedule a maintenance to perform the migration at a
convenient time.

Initialising the migration itself is a short offline operation, but takes only a
few seconds until the VM is then started again. The actual data migration
happens transparently in the background.

To speed up the process you can take the VM offline and online again to
initiate the migration immediately.


## Growing and shrinking disks

Virtual disks can be grown on the fly without shutting down the VM but shrinking
is not supported.

When *growing* a virtual disk, we enlarge the underlying RBD volume, adapt the
partition table and resize the main filesystem. This procedure is fully
transpart and can be performed without downtime.

*Shrinking* a virtual disk is not supported. To shrink a disk you need to 
provision a new VM and copy the data to a smaller disk.

[rbd volume]: http://docs.ceph.com/docs/master/architecture/

