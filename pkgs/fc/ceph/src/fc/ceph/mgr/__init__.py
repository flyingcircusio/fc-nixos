import fc.ceph

from . import nautilus


class Manager(fc.ceph.VersionedSubsystem):

    nautilus = nautilus.Manager
