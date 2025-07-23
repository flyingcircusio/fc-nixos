# ceph development deployment

A deployment for bootstrapping an interactive minimal (fc-)ceph cluster in a dev VM for testing and hands-on development.

## cluster management

It is expected that you work as a `root` user throughout the process, access to that user is possible via `sudo -i`.

`init_cluster create` and `init_cluster destroy` manage a single-host minimal ceph cluster based on loopback devices. \
That alias points to the file `/root/deployment/work/ceph/init_cluster.py` that may be changed interactively on the dev VM to avoid deployment round trips.
