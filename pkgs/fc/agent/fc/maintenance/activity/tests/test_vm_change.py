from io import StringIO

import yaml
from fc.maintenance.activity import Activity, RebootType
from fc.maintenance.activity.vm_change import VMChangeActivity
from pytest import fixture
from rich.console import Console

SERIALIZED_ACTIVITY = f"""\
!!python/object:fc.maintenance.activity.vm_change.VMChangeActivity
current_cores: 1
current_memory: 1024
estimate: !!python/object:fc.maintenance.estimate.Estimate
  value: 300.0
reboot_needed: !!python/object/apply:fc.maintenance.activity.RebootType
- poweroff
wanted_cores: 2
wanted_memory: 2048
"""


@fixture
def activity(logger):
    activity = VMChangeActivity(wanted_memory=2048, wanted_cores=2, log=logger)
    activity.reboot_needed = RebootType.COLD
    activity.current_memory = 1024
    activity.current_cores = 1
    return activity


def test_vm_change_dont_merge_incompatible(activity):
    other = Activity()
    result = activity.merge(other)
    assert result.is_effective is False
    assert result.is_significant is False
    assert result.merged is None
    assert not result.changes


def test_vm_change_merge_same(activity):
    result = activity.merge(activity)
    assert result.is_effective is True
    assert result.is_significant is False
    assert result.merged is activity
    assert not result.changes


def test_vm_change_merge_different_is_an_insignificant_update(activity):
    other = VMChangeActivity(wanted_memory=4096, wanted_cores=4)
    result = activity.merge(other)
    assert result.merged is activity
    assert result.merged is not other
    assert result.is_effective is True
    assert result.is_significant is False
    assert result.changes == {
        "cores": {"before": 2, "after": 4},
        "memory": {"before": 2048, "after": 4096},
    }


def test_reboot_merge_into_ineffective_is_an_significant_update(activity):
    activity.current_memory = activity.wanted_memory
    activity.current_cores = activity.wanted_cores
    other = VMChangeActivity(wanted_memory=4096, wanted_cores=4)
    result = activity.merge(other)
    assert result.merged is activity
    assert result.is_effective is True
    assert result.is_significant is True
    assert result.changes == {
        "cores": {"before": 2, "after": 4},
        "memory": {"before": 2048, "after": 4096},
    }


def test_vm_change_merge_inverse_is_no_op(activity):
    other = VMChangeActivity(
        wanted_memory=activity.current_memory,
        wanted_cores=activity.current_cores,
    )
    result = activity.merge(other)
    assert result.merged is activity
    assert result.is_effective is False
    assert result.is_significant is False
    assert result.changes == {
        "cores": {"before": 2, "after": 1},
        "memory": {"before": 2048, "after": 1024},
    }


def test_reboot_activity_serialize(activity):
    serialized = yaml.dump(activity)
    print(serialized)
    assert serialized == SERIALIZED_ACTIVITY


def test_update_activity_deserialize(activity, logger):
    deserialized = yaml.load(SERIALIZED_ACTIVITY, Loader=yaml.UnsafeLoader)
    deserialized.set_up_logging(logger)
    assert deserialized.__getstate__() == activity.__getstate__()


def test_rich_print(activity):
    activity.reboot_needed = RebootType.COLD
    console = Console(file=StringIO())
    console.print(activity)
    str_output = console.file.getvalue()
    assert (
        "fc.maintenance.activity.vm_change.VMChangeActivity (cold reboot needed)\n"
        == str_output
    )
