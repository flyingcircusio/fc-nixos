import fc.ceph

from . import jewel, luminous

DEFAULT_JOURNAL_SIZE = "10g"
OBJECTSTORE_TYPES = ["filestore", "bluestore"]


class OSDManager(fc.ceph.VersionedSubsystem):

    jewel = jewel.OSDManager
    luminous = luminous.OSDManager
