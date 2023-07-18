import fc.ceph

from . import luminous, nautilus


class Manager(fc.ceph.VersionedSubsystem):

    luminous = luminous.Manager
    nautilus = nautilus.Manager
