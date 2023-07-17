import fc.ceph

from . import jewel, luminous, nautilus


class Monitor(fc.ceph.VersionedSubsystem):
    jewel = jewel.Monitor
    luminous = luminous.Monitor
    nautilus = nautilus.Monitor
