import fc.ceph

from . import nautilus, pacific


class RgwUserManager(fc.ceph.VersionedSubsystem):
    pacific = pacific.RgwUserManager
    nautilus = nautilus.RgwUserManager
