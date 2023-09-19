import fc.ceph

from . import nautilus


class KeyManager(fc.ceph.VersionedSubsystem):

    nautilus = nautilus.KeyManager
