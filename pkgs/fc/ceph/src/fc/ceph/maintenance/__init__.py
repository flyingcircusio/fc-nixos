import fc.ceph

from . import jewel, luminous, nautilus


class MaintenanceTasks(fc.ceph.VersionedSubsystem):

    jewel = jewel.MaintenanceTasks
    luminous = luminous.MaintenanceTasks
    nautilus = nautilus.MaintenanceTasks
