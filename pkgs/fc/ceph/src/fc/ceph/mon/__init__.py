import fc.ceph

from . import nautilus


class Monitor(fc.ceph.VersionedSubsystem):

    nautilus = nautilus.Monitor
