import fc.ceph

from . import nautilus


class MaintenanceTasks(fc.ceph.VersionedSubsystem):
    pacific = nautilus.MaintenanceTasks
    nautilus = nautilus.MaintenanceTasks
