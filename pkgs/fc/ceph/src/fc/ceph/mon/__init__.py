import fc.ceph

from . import nautilus


class Monitor(fc.ceph.VersionedSubsystem):
    pacific = nautilus.Monitor
    nautilus = nautilus.Monitor
