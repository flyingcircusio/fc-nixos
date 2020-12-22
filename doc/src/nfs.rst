.. _nixos2-nfs:

NFS
===

Maintains a NFS share to access a data pool from multiple VMs. The NFS share is
bound to one project and one datacenter location.

Components
----------

* nfs_rg_share
* nfs_rg_client


Configuration
-------------

The NFS configuration is fully managed and located in
:file:`/etc/exports` for the NFS server and :file:`/etc/fstab` for the NFS
clients.

The NFS server is set up to run in sync mode, so any system call that writes
data to files on the NFS share causes that data to be flushed to the server
before the system call returns control to user space. This provides greater data
cache coherence among clients, but at a significant performance cost.

Interaction
-----------

All NFS clients mount the NFS share at :file:`/mnt/nfs/shared`. This directory is
readable and writable by any service user. Application may use this directory to
store their data to be available across multiple VMs.

The NFS server stores its data at :file:`/srv/nfs/shared`. This directory is also
readable and writable by any service user. We recommend not to directly access
this directory if there is no special need to do so, but to also use the NFS
client component on the server VM.

.. vim: set spell spelllang=en:
