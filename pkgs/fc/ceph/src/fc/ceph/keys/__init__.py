import fc.ceph

from . import nautilus


class KeyManager(fc.ceph.VersionedSubsystem):
    pacific = nautilus.KeyManager
    nautilus = nautilus.KeyManager
