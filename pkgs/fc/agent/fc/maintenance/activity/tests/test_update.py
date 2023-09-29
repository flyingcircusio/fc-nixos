import textwrap
from io import StringIO
from unittest.mock import create_autospec

import responses
import yaml
from fc.maintenance import state
from fc.maintenance.activity import Activity, RebootType
from fc.maintenance.activity.update import UpdateActivity
from fc.util.channel import Channel
from fc.util.nixos import (
    BuildFailed,
    ChannelException,
    ChannelUpdateFailed,
    RegisterFailed,
    SwitchFailed,
)
from pytest import fixture
from rich.console import Console

CURRENT_BUILD = 93111
NEXT_BUILD = 93222
NEXT_NEXT_BUILD = 93333
CURRENT_CHANNEL_URL = f"https://hydra.flyingcircus.io/build/{CURRENT_BUILD}/download/1/nixexprs.tar.xz"
NEXT_CHANNEL_URL = f"https://hydra.flyingcircus.io/build/{NEXT_BUILD}/download/1/nixexprs.tar.xz"
ENVIRONMENT = "fc-21.05-production"
CURRENT_VERSION = "21.05.1233.a9cc58d"
NEXT_VERSION = "21.05.1235.bacc11d"
CURRENT_SYSTEM_PATH = f"/nix/store/zbx8i9v4j8dzlwp83qvrzjgvj7d0qm0d-nixos-system-test-{NEXT_VERSION}"
NEXT_SYSTEM_PATH = f"/nix/store/v49jzgwblcn9vkrmpz92kzw5pkbsn0vz-nixos-system-test-{NEXT_VERSION}"
CURRENT_KERNEL_VERSION = "5.10.45"
NEXT_KERNEL_VERSION = "5.10.50"

UNIT_CHANGES = {
    "reload": ["nginx.service"],
    "restart": ["telegraf.service"],
    "start": ["postgresql.service"],
    "stop": ["postgresql.service"],
}

CHANGELOG = textwrap.dedent(
    f"""\
    System update: {CURRENT_VERSION} -> {NEXT_VERSION}

    Will reboot after the update.

    Start/Stop: postgresql
    Restart: telegraf
    Reload: nginx

    Environment: {ENVIRONMENT} (unchanged)
    Build number: {CURRENT_BUILD} -> {NEXT_BUILD}
    Channel URL: {NEXT_CHANNEL_URL}"""
)

SERIALIZED_ACTIVITY = f"""\
!!python/object:fc.maintenance.activity.update.UpdateActivity
current_channel_url: https://hydra.flyingcircus.io/build/93111/download/1/nixexprs.tar.xz
current_environment: fc-21.05-production
current_kernel: 5.10.45
current_system: {CURRENT_SYSTEM_PATH}
current_version: 21.05.1233.a9cc58d
next_channel_url: https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz
next_environment: fc-21.05-production
next_kernel: 5.10.50
next_system: {NEXT_SYSTEM_PATH}
next_version: 21.05.1235.bacc11d
reboot_needed: !!python/object/apply:fc.maintenance.activity.RebootType
- reboot
unit_changes:
  reload:
  - nginx.service
  restart:
  - telegraf.service
  start:
  - postgresql.service
  stop:
  - postgresql.service
"""


@fixture
def activity(logger, nixos_mock):
    activity = UpdateActivity(next_channel_url=NEXT_CHANNEL_URL, log=logger)
    activity.current_channel_url = CURRENT_CHANNEL_URL
    activity.current_environment = ENVIRONMENT
    activity.current_version = CURRENT_VERSION
    activity.current_kernel = CURRENT_KERNEL_VERSION
    activity.next_channel_url = NEXT_CHANNEL_URL
    activity.next_environment = ENVIRONMENT
    activity.next_kernel = NEXT_KERNEL_VERSION
    activity.next_system = NEXT_SYSTEM_PATH
    activity.next_version = NEXT_VERSION
    activity.reboot_needed = RebootType.WARM
    activity.unit_changes = UNIT_CHANGES
    return activity


def test_update_dont_merge_incompatible(activity):
    other = Activity()
    result = activity.merge(other)
    assert result.is_effective is False
    assert result.is_significant is False
    assert result.merged is None
    assert not result.changes


def test_update_merge_same(activity):
    # Given another activity which is exactly the same
    other = UpdateActivity(NEXT_CHANNEL_URL)
    other.__dict__.update(activity.__getstate__())
    result = activity.merge(other)
    # Then the merge result should be the original activity
    assert result.merged is activity
    assert result.is_effective is True
    assert result.is_significant is False
    assert not result.changes


def test_update_merge_additional_reload_is_an_insignificant_update(activity):
    # Given another activity which has a different channel URl and reloads an
    # additional service.
    channel_url = (
        "https://hydra.flyingcircus.io/build/100000/download/1/nixexprs.tar.xz"
    )

    other = UpdateActivity(channel_url)
    other.unit_changes = {
        **UNIT_CHANGES,
        "reload": {"nginx.service", "dbus.service"},
    }
    result = activity.merge(other)
    # Then the merge result should be a new activity and the change is
    # insignificant.
    assert result.merged is not activity
    assert result.merged is not other
    assert result.is_effective is True
    assert result.is_significant is False
    assert result.changes == {
        "added_unit_changes": {"reload": {"dbus.service"}},
        "removed_unit_changes": {},
    }


def test_update_merge_more_unit_changes_is_a_significant_update(activity):
    # Given another activity which has a different channel url and restarts
    # different units.
    channel_url = (
        "https://hydra.flyingcircus.io/build/100000/download/1/nixexprs.tar.xz"
    )

    other = UpdateActivity(channel_url)
    other.unit_changes = {**UNIT_CHANGES, "restart": {"mysql.service"}}
    result = activity.merge(other)
    # Then the merge result should be a new activity and the change is
    # significant.
    assert result.merged is not activity
    assert result.merged is not other
    assert result.is_effective is True
    assert result.is_significant is True
    assert result.changes == {
        "added_unit_changes": {"restart": {"mysql.service"}},
        "removed_unit_changes": {"restart": {"telegraf.service"}},
    }


@fixture
def nixos_mock(monkeypatch):
    import fc.util.nixos

    def fake_get_fc_channel_build(channel_url, _):
        if channel_url == CURRENT_CHANNEL_URL:
            return CURRENT_BUILD
        elif channel_url == NEXT_CHANNEL_URL:
            return NEXT_BUILD

    def fake_channel_version(channel_url):
        if channel_url == CURRENT_CHANNEL_URL:
            return CURRENT_VERSION
        elif channel_url == NEXT_CHANNEL_URL:
            return NEXT_VERSION

    def fake_changed_kernel_version(path):
        if path == CURRENT_SYSTEM_PATH + "/kernel":
            return CURRENT_KERNEL_VERSION
        elif path == NEXT_SYSTEM_PATH + "/kernel":
            return NEXT_KERNEL_VERSION

    mocked = create_autospec(
        fc.util.nixos,
        ChannelException=ChannelException,
        ChannelUpdateFailed=ChannelUpdateFailed,
        BuildFailed=BuildFailed,
        SwitchFailed=SwitchFailed,
        RegisterFailed=RegisterFailed,
    )

    mocked.format_unit_change_lines = fc.util.nixos.format_unit_change_lines
    mocked.get_fc_channel_build = fake_get_fc_channel_build
    mocked.channel_version = fake_channel_version
    mocked.kernel_version = fake_changed_kernel_version
    mocked.resolve_url_redirects = lambda url: url
    mocked.build_system.return_value = NEXT_SYSTEM_PATH
    mocked.current_nixos_channel_url.return_value = CURRENT_CHANNEL_URL
    mocked.dry_activate_system.return_value = UNIT_CHANGES
    mocked.running_system_version.return_value = CURRENT_VERSION
    mocked.current_system.return_value = CURRENT_SYSTEM_PATH
    mocked.current_fc_environment_name.return_value = ENVIRONMENT
    monkeypatch.setattr("fc.maintenance.activity.update.nixos", mocked)

    return mocked


def test_update_activity(nixos_mock):
    activity = UpdateActivity(NEXT_CHANNEL_URL, ENVIRONMENT)

    assert activity
    assert activity.current_version == CURRENT_VERSION
    assert activity.next_version == NEXT_VERSION
    assert activity.current_environment == ENVIRONMENT
    assert activity.current_channel_url == CURRENT_CHANNEL_URL


def test_update_activity_serialize(activity):
    serialized = yaml.dump(activity)
    assert serialized == SERIALIZED_ACTIVITY


def test_update_activity_deserialize(activity, logger):
    deserialized = yaml.load(SERIALIZED_ACTIVITY, Loader=yaml.UnsafeLoader)
    deserialized.set_up_logging(logger)
    assert deserialized.__getstate__() == activity.__getstate__()


def test_update_activity_prepare(log, logger, tmp_path, activity, nixos_mock):
    activity.prepare()

    nixos_mock.build_system.assert_called_once_with(
        NEXT_CHANNEL_URL, out_link="/run/next-system", log=activity.log
    )

    nixos_mock.dry_activate_system.assert_called_once_with(
        NEXT_SYSTEM_PATH, activity.log
    )

    assert (
        activity.reboot_needed == RebootType.WARM
    ), "expected warm reboot request"
    assert activity.changelog == CHANGELOG

    assert log.has(
        "update-prepare-start",
        next_channel=NEXT_CHANNEL_URL,
        next_environment=ENVIRONMENT,
    )
    assert log.has(
        "update-kernel-changed",
        current_kernel=CURRENT_KERNEL_VERSION,
        next_kernel=NEXT_KERNEL_VERSION,
    )


def test_update_activity_run(log, nixos_mock, activity, logger):
    activity.run()

    assert activity.returncode == 0
    nixos_mock.update_system_channel.assert_called_with(
        activity.next_channel_url, log=activity.log
    )
    nixos_mock.build_system.assert_called_with(
        activity.next_channel_url, log=activity.log
    )
    nixos_mock.register_system_profile.assert_called_with(
        NEXT_SYSTEM_PATH, log=activity.log
    )
    nixos_mock.switch_to_system.assert_called_with(
        NEXT_SYSTEM_PATH, lazy=False, log=activity.log
    )
    assert log.has("update-run-succeeded")


def test_update_activity_run_unchanged(log, nixos_mock, activity):
    activity.current_system = activity.next_system

    activity.run()

    nixos_mock.update_system_channel.assert_called_with(
        activity.next_channel_url, log=activity.log
    )
    nixos_mock.build_system.assert_not_called()

    assert activity.returncode == 0


def test_update_activity_run_update_system_channel_fails(
    log, nixos_mock, activity
):
    nixos_mock.update_system_channel.side_effect = ChannelUpdateFailed(
        stdout="stdout", stderr="stderr"
    )

    activity.run()

    assert activity.returncode == 1
    assert log.has("update-run-error", returncode=1)


def test_update_activity_build_system_fails(log, nixos_mock, activity):
    nixos_mock.build_system.side_effect = BuildFailed(
        msg="msg", stdout="stdout", stderr="stderr"
    )

    activity.run()

    assert activity.returncode == 2
    assert log.has("update-run-error", returncode=2)


def test_update_activity_register_system_profile_fails(
    log, nixos_mock, activity
):
    nixos_mock.register_system_profile.side_effect = RegisterFailed(
        msg="msg", stdout="stdout", stderr="stderr"
    )

    activity.run()

    assert activity.returncode == 3
    assert log.has("update-run-error", returncode=3)


def test_update_activity_switch_to_system_fails(log, nixos_mock, activity):
    nixos_mock.switch_to_system.side_effect = SwitchFailed(stdout="stdout")

    activity.run()

    assert activity.returncode == state.EXIT_TEMPFAIL
    assert log.has("update-run-tempfail", returncode=state.EXIT_TEMPFAIL)


def test_update_activity_from_enc(
    log, mocked_responses, nixos_mock, logger, monkeypatch
):
    environment = "fc-21.05-dev"
    current_channel_url = (
        "https://hydra.flyingcircus.io/build/93000/download/1/nixexprs.tar.xz"
    )
    next_channel_url = (
        "https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz"
    )
    current_version = "21.05.1233.a9cc58d"
    next_version = "21.05.1235.bacc11d"

    enc = {
        "parameters": {
            "environment_url": next_channel_url,
            "environment": environment,
        }
    }

    mocked_responses.add(responses.HEAD, current_channel_url)
    mocked_responses.add(responses.HEAD, next_channel_url)
    monkeypatch.setattr(
        "fc.util.nixos.channel_version", (lambda c: next_version)
    )

    current_channel = Channel(logger, current_channel_url)
    current_channel.version = lambda *a: current_version
    monkeypatch.setattr(
        "fc.manage.manage.Channel.current", lambda *a: current_channel
    )
    activity = UpdateActivity.from_enc(logger, enc)
    assert activity


def test_update_from_enc_no_enc(log, logger):
    activity = UpdateActivity.from_enc(logger, {})
    assert activity is None
    assert log.has("enc-data-missing")


def test_update_from_enc_incompatible_with_local_channel(log, logger):
    """Given an unchanged channel url, should not prepare an update activity"""
    enc = {
        "parameters": {
            "environment_url": "file://test",
            "environment": "dev-checkout-23.05",
        }
    }

    activity = UpdateActivity.from_enc(logger, enc)
    assert activity is None
    assert log.has("update-from-enc-local-channel")


def test_rich_print(activity):
    activity.reboot_needed = RebootType.WARM
    console = Console(file=StringIO())
    console.print(activity)
    str_output = console.file.getvalue()
    assert (
        "fc.maintenance.activity.update.UpdateActivity (warm reboot needed)\n"
        == str_output
    )
