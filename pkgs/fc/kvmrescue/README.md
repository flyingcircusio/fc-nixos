# fc-kvmrescue

Walks an operator through evacuating the VMs of a dead KVM host: fencing the
host, breaking the Ceph locks it still holds, asking the directory to move its
VMs, watching them come back, and cleaning up afterwards.

The whole tool is one module, `fc_kvmrescue.py`. It declares its dependencies
inline (PEP 723), so it also runs straight from a checkout without any of the
setup below:

    ./fc_kvmrescue.py <kvmhost>

A rescue is identified by the host being rescued: state
lives in `/var/lib/fc-kvmrescue/<kvmhost>.json`, so a second run for the same
host resumes the rescue in progress rather than starting a rival one.

Use `--dry-run` to walk the sequence without touching anything: every command
that would change the cluster or the host is printed instead of run.

## Running the tests

    uv run pytest
