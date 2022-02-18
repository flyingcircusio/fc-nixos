import textwrap
from unittest.mock import MagicMock, Mock, create_autospec

import pytest
import structlog
import yaml
from fc.maintenance.activity import RebootType
from fc.maintenance.activity.update import UpdateActivity
from fc.manage.manage import Channel
from fc.util.nixos import (
    BuildFailed,
    ChannelException,
    ChannelUpdateFailed,
    RegisterFailed,
    SwitchFailed,
)
from pytest import fixture

CURRENT_BUILD = 93111
NEXT_BUILD = 93222
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
    Build number: {CURRENT_BUILD} -> {NEXT_BUILD}
    Environment: {ENVIRONMENT} (unchanged)

    Will reboot after the update.
    Stop: postgresql
    Restart: telegraf
    Start: postgresql
    Reload: nginx

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
def logger():
    return structlog.get_logger()


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
    activity.unit_changes = UNIT_CHANGES
    return activity


@fixture
def nixos_mock(monkeypatch):
    import fc.util.nixos

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


def test_update_activity_from_system_changed(nixos_mock):
    activity = UpdateActivity.from_system_if_changed(
        NEXT_CHANNEL_URL, ENVIRONMENT
    )

    assert activity
    assert activity.current_version == CURRENT_VERSION
    assert activity.next_version == NEXT_VERSION
    assert activity.current_environment == ENVIRONMENT
    assert activity.current_channel_url == CURRENT_CHANNEL_URL


def test_update_activity_serialize(activity):
    serialized = yaml.dump(activity)
    assert serialized == SERIALIZED_ACTIVITY


def test_update_activity_deserialize(activity, logger):
    deserialized = yaml.load(SERIALIZED_ACTIVITY, Loader=yaml.FullLoader)
    deserialized.set_up_logging(logger)
    assert deserialized.__getstate__() == activity.__getstate__()


def test_update_activity_prepare(log, logger, tmp_path, activity, nixos_mock):
    activity.prepare()

    nixos_mock.build_system.assert_called_once_with(
        NEXT_CHANNEL_URL, out_link="/run/next-system", log=logger
    )

    nixos_mock.dry_activate_system.assert_called_once_with(
        NEXT_SYSTEM_PATH, logger
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
        activity.next_channel_url, log=logger
    )
    nixos_mock.build_system.assert_called_with(
        activity.next_channel_url, log=logger
    )
    nixos_mock.switch_to_system.assert_called_with(
        NEXT_SYSTEM_PATH, lazy=False, log=logger
    )
    log.has("update-run-succeeded")


def test_update_activity_run_unchanged(log, nixos_mock, activity):
    nixos_mock.running_system_version.return_value = activity.next_version

    activity.run()

    assert activity.returncode == 0
    log.has("update-run-skip")


def test_update_activity_run_update_system_channel_fails(
    log, nixos_mock, activity
):
    nixos_mock.update_system_channel.side_effect = ChannelUpdateFailed(
        stdout="stdout", stderr="stderr"
    )

    activity.run()

    assert activity.returncode == 1
    log.has("update-run-failed", returncode=1)


def test_update_activity_build_system_fails(log, nixos_mock, activity):
    nixos_mock.build_system.side_effect = BuildFailed(
        msg="msg", stdout="stdout", stderr="stderr"
    )

    activity.run()

    assert activity.returncode == 2
    log.has("update-run-failed", returncode=2)


def test_update_activity_switch_to_system_fails(log, nixos_mock, activity):
    nixos_mock.switch_to_system.side_effect = SwitchFailed(stdout="stdout")

    activity.run()

    assert activity.returncode == 3
    log.has("update-run-failed", returncode=3)
