import fc.ceph

from . import luminous


class Manager(fc.ceph.VersionedSubsystem):

    luminous = luminous.Manager
