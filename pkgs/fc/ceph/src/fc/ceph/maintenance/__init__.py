import fc.ceph

from . import jewel, luminous


class MaintenanceTasks(fc.ceph.VersionedSubsystem):

    jewel = jewel.MaintenanceTasks
    luminous = luminous.MaintenanceTasks
