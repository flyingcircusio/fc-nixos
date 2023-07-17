import fc.ceph

from . import jewel, luminous


class KeyManager(fc.ceph.VersionedSubsystem):
    jewel = jewel.KeyManager
    luminous = luminous.KeyManager
    nautilus = luminous
