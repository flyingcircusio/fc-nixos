import fc.ceph

from . import jewel, luminous


class Monitor(fc.ceph.VersionedSubsystem):

    jewel = jewel.Monitor
    luminous = luminous.Monitor
