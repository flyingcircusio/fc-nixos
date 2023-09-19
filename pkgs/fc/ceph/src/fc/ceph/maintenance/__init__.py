import fc.ceph

from . import nautilus


class MaintenanceTasks(fc.ceph.VersionedSubsystem):

    nautilus = nautilus.MaintenanceTasks
