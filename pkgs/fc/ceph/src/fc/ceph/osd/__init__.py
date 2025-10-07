import fc.ceph

from . import nautilus

DEFAULT_JOURNAL_SIZE = "10g"
OBJECTSTORE_TYPES = ["filestore", "bluestore"]


class OSDManager(fc.ceph.VersionedSubsystem):
    pacific = nautilus.OSDManager
    nautilus = nautilus.OSDManager
