import pytest
import yaml
from fc.maintenance.activity import Activity, RebootType
from fc.maintenance.activity.reboot import RebootActivity
from pytest import fixture

SERIALIZED_ACTIVITY = f"""\
!!python/object:fc.maintenance.activity.reboot.RebootActivity
reboot_needed: !!python/object/apply:fc.maintenance.activity.RebootType
- reboot
"""


@fixture
def warm(logger):
    activity = RebootActivity(RebootType.WARM, log=logger)
    return activity


@fixture
def cold(logger):
    activity = RebootActivity(RebootType.COLD, log=logger)
    return activity


def test_reboot_accepts_enum_reboot_type_warm():
    activity = RebootActivity(RebootType.WARM)
    assert activity.reboot_needed == RebootType.WARM


def test_reboot_accepts_enum_reboot_type_cold():
    activity = RebootActivity(RebootType.COLD)
    assert activity.reboot_needed == RebootType.COLD


def test_reboot_accepts_str_reboot():
    activity = RebootActivity("reboot")
    assert activity.reboot_needed == RebootType.WARM


def test_reboot_accepts_str_poweroff():
    activity = RebootActivity("poweroff")
    assert activity.reboot_needed == RebootType.COLD


def test_reboot_should_reject_invalid_str():
    with pytest.raises(ValueError):
        RebootActivity("kaput")


def test_reboot_comment_warm(warm):
    assert warm.comment == "Scheduled reboot"


def test_reboot_comment_cold(cold):
    assert cold.comment == "Scheduled cold boot"


def test_reboot_dont_merge_incompatible(warm):
    other = Activity()
    result = warm.merge(other)
    assert result.is_effective is False
    assert result.is_significant is False
    assert result.merged is None
    assert not result.changes


def test_reboot_merge_warm_into_cold_is_an_insignificant_update(warm, cold):
    result = cold.merge(warm)
    assert result.merged is cold
    assert result.is_effective is True
    assert result.is_significant is False
    assert not result.changes


def test_reboot_merge_warm_is_an_insignificant_update(warm):
    other_warm = RebootActivity(RebootType.WARM)
    result = warm.merge(other_warm)
    assert result.merged is warm
    assert result.is_effective is True
    assert result.is_significant is False
    assert not result.changes


def test_reboot_merge_cold_is_an_significant_update(warm, cold):
    original = warm
    result = original.merge(cold)
    assert result.merged is original
    assert result.is_effective is True
    assert result.is_significant is True
    assert result.changes == {"before": "reboot", "after": "poweroff"}


def test_reboot_activity_serialize(warm):
    serialized = yaml.dump(warm)
    print(serialized)
    assert serialized == SERIALIZED_ACTIVITY


def test_update_activity_deserialize(warm, logger):
    deserialized = yaml.load(SERIALIZED_ACTIVITY, Loader=yaml.UnsafeLoader)
    deserialized.set_up_logging(logger)
    assert deserialized.__getstate__() == warm.__getstate__()
