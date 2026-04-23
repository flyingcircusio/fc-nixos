import fc.ceph

from . import nautilus


class Manager(fc.ceph.VersionedSubsystem):
    pacific = nautilus.Manager
    nautilus = nautilus.Manager
