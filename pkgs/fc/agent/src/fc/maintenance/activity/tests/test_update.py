import textwrap
from io import StringIO
from unittest.mock import Mock, create_autospec
from pathlib import Path

import responses
import yaml
import fc.util.nixos
from fc.maintenance import Request, state
from fc.maintenance.activity import Activity, RebootType
from fc.maintenance.activity.update import UpdateActivity
from fc.util.channel import Channel
from fc.util.nixos import (
    BuildFailed,
    ChannelException,
    ChannelUpdateFailed,
    RegisterFailed,
    SwitchFailed,
    KernelIdentifier,
)
from pytest import fixture
from rich.console import Console

CURRENT_BUILD = 93111
NEXT_BUILD = 93222
NEXT_NEXT_BUILD = 93333

CHANGELOG_URL = "https://doc.flyingcircus.io/platform/changes/2021/r003.html"

CURRENT_CHANNEL_URL = f"https://hydra.flyingcircus.io/build/{CURRENT_BUILD}/download/1/nixexprs.tar.xz"
NEXT_CHANNEL_URL = f"https://hydra.flyingcircus.io/build/{NEXT_BUILD}/download/1/nixexprs.tar.xz"

ENVIRONMENT = "fc-21.05-production"

CURRENT_BUILD_ID = "21.05.1233.a9cc58d"
CURRENT_VERSION_ID = "21.05"
NEXT_BUILD_ID = "21.05.1235.bacc11d"
NEXT_VERSION_ID = "21.05"

CURRENT_SYSTEM_PATH = f"/nix/store/zbx8i9v4j8dzlwp83qvrzjgvj7d0qm0d-nixos-system-test-{NEXT_BUILD_ID}"
NEXT_SYSTEM_PATH = f"/nix/store/v49jzgwblcn9vkrmpz92kzw5pkbsn0vz-nixos-system-test-{NEXT_BUILD_ID}"

CURRENT_KERNEL_VERSION = KernelIdentifier("asdfgh-linux-5.10.45")
NEXT_KERNEL_VERSION = KernelIdentifier("qwertz-linux-5.10.50")

UNIT_CHANGES = {
    "reload": ["nginx.service"],
    "restart": ["telegraf.service"],
    "start": ["postgresql.service"],
    "stop": ["postgresql.service"],
}

SUMMARY = textwrap.dedent(
    f"""\
    System update: {CURRENT_BUILD_ID} -> {NEXT_BUILD_ID}

    Will reboot after the update.

    Start/Stop: postgresql
    Restart: telegraf
    Reload: nginx

    Environment: {ENVIRONMENT} (unchanged)
    Build number: {CURRENT_BUILD} -> {NEXT_BUILD}
    Channel URL: {NEXT_CHANNEL_URL}"""
)

OUTDATED_SERIALIZED_REQUEST = f"""\
!!python/object:fc.maintenance.request.Request
_comment: null
_estimate: null
_reqid: ZXutH76zLeQ9XmpDvW3axh
_reqmanager: null
activity: !!python/object:fc.maintenance.activity.update.UpdateActivity
  current_channel_url: https://hydra.flyingcircus.io/build/93111/download/1/nixexprs.tar.xz
  current_environment: fc-21.05-production
  current_kernel: 5.10.45
  current_system: {CURRENT_SYSTEM_PATH}
  current_version: 21.05.1233.a9cc58d
  next_channel_url: https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz
  next_environment: fc-21.05-production
  next_kernel: !!python/object:fc.util.nixos.KernelIdentifier
    store_name: qwertz-linux-5.10.50
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
    - postgresql.services
added_at: 2023-07-11 18:38:59.850059+00:00
dir: /var/spool/maintenance/requests/testid
last_scheduled_at: null
next_due: null
state: !!python/object/apply:fc.maintenance.state.State
- d
updated_at: null
"""

SERIALIZED_ACTIVITY = f"""\
!!python/object:fc.maintenance.activity.update.UpdateActivity
next_channel_url: https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz
next_environment: fc-21.05-production
next_kernel: !!python/object:fc.util.nixos.KernelIdentifier
  store_name: qwertz-linux-5.10.50
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
def activity(logger, nixos_mock, tmp_path):
    activity = UpdateActivity(next_channel_url=NEXT_CHANNEL_URL, log=logger)
    activity.next_channel_url = NEXT_CHANNEL_URL
    activity.next_environment = ENVIRONMENT
    activity.next_kernel = NEXT_KERNEL_VERSION
    activity.next_system = NEXT_SYSTEM_PATH
    activity.next_version = NEXT_BUILD_ID
    activity.reboot_needed = RebootType.WARM
    activity.unit_changes = UNIT_CHANGES
    activity.lock_dir = tmp_path
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


@fixture()
def mock_resolve_url_redirects(monkeypatch):
    m = Mock()
    m.side_effect = lambda url: url
    monkeypatch.setattr("fc.util.nixos.resolve_url_redirects", m)
    return m


@fixture
def nixos_mock(monkeypatch):
    import fc.util.nixos

    def fake_get_fc_channel_build(channel_url, _):
        if channel_url == CURRENT_CHANNEL_URL:
            return mocked.CURRENT_BUILD
        elif channel_url == NEXT_CHANNEL_URL:
            return mocked.NEXT_BUILD

    def fake_channel_version(channel_url):
        if channel_url == CURRENT_CHANNEL_URL:
            return mocked.CURRENT_BUILD_ID
        elif channel_url == NEXT_CHANNEL_URL:
            return mocked.NEXT_BUILD_ID

    def fake_changed_system_kernel(path):
        if path == Path(CURRENT_SYSTEM_PATH):
            return CURRENT_KERNEL_VERSION
        elif path == Path(NEXT_SYSTEM_PATH):
            return NEXT_KERNEL_VERSION

    def fake_os_release(path=None):
        if path in [CURRENT_SYSTEM_PATH, None]:
            return {
                "BUILD_ID": mocked.CURRENT_BUILD_ID,
                "VERSION_ID": mocked.CURRENT_VERSION_ID,
            }
        elif path == NEXT_SYSTEM_PATH:
            return {
                "BUILD_ID": mocked.NEXT_BUILD_ID,
                "VERSION_ID": mocked.NEXT_VERSION_ID,
            }

    mocked = create_autospec(
        fc.util.nixos,
        ChannelException=ChannelException,
        ChannelUpdateFailed=ChannelUpdateFailed,
        BuildFailed=BuildFailed,
        SwitchFailed=SwitchFailed,
        RegisterFailed=RegisterFailed,
    )

    mocked.CURRENT_BUILD = CURRENT_BUILD
    mocked.CURRENT_BUILD_ID = CURRENT_BUILD_ID
    mocked.CURRENT_VERSION_ID = CURRENT_VERSION_ID
    mocked.NEXT_BUILD = NEXT_BUILD
    mocked.NEXT_BUILD_ID = NEXT_BUILD_ID
    mocked.NEXT_VERSION_ID = NEXT_VERSION_ID

    mocked.format_unit_change_lines = fc.util.nixos.format_unit_change_lines
    mocked.get_fc_channel_build = fake_get_fc_channel_build
    mocked.channel_version = fake_channel_version
    mocked.system_kernel = fake_changed_system_kernel
    mocked.resolve_url_redirects = lambda url: url
    mocked.os_release = fake_os_release
    mocked.build.return_value = NEXT_SYSTEM_PATH
    mocked.current_nixos_channel_url.return_value = CURRENT_CHANNEL_URL
    mocked.dry_activate_system.return_value = UNIT_CHANGES
    mocked.current_system.return_value = CURRENT_SYSTEM_PATH
    mocked.current_fc_environment_name.return_value = ENVIRONMENT
    monkeypatch.setattr("fc.maintenance.activity.update.nixos", mocked)

    return mocked


def test_update_activity(nixos_mock):
    activity = UpdateActivity(NEXT_CHANNEL_URL, ENVIRONMENT)

    assert activity
    assert activity.current_version == CURRENT_BUILD_ID
    assert activity.next_version == NEXT_BUILD_ID
    assert activity.current_environment == ENVIRONMENT
    assert activity.current_channel_url == CURRENT_CHANNEL_URL


def test_update_activity_serialize(activity):
    serialized = yaml.dump(activity)
    assert serialized == SERIALIZED_ACTIVITY


def test_update_activity_deserialize(activity, logger):
    deserialized = yaml.load(SERIALIZED_ACTIVITY, Loader=yaml.UnsafeLoader)
    deserialized.set_up_logging(logger)
    assert deserialized.__getstate__() == activity.__getstate__()


def test_update_activity_loading_outdated_serialization_should_work(
    logger, tmp_path, agent_configparser, nixos_mock
):
    request_path = tmp_path / "request.yaml"
    request_path.write_text(OUTDATED_SERIALIZED_REQUEST)
    request = Request.load(tmp_path, agent_configparser, logger, 1800)
    activity = request.activity
    assert activity.summary
    assert activity.__rich__()


def test_update_activity_prepare(
    log, logger, tmp_path, activity, nixos_mock, mock_resolve_url_redirects
):
    activity.prepare()

    nixos_mock.build.assert_called_once_with(
        Channel(activity.log, NEXT_CHANNEL_URL),
        out_link="/run/next-system",
        log=activity.log,
    )

    nixos_mock.dry_activate_system.assert_called_once_with(
        NEXT_SYSTEM_PATH, activity.log
    )

    assert activity.reboot_needed == RebootType.WARM, (
        "expected warm reboot request"
    )
    assert activity.summary == SUMMARY

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


def test_update_nfs_reboot_required(
    log, logger, tmp_path, activity, nixos_mock
):
    # I'd rather like to call prepare() here but the overall logic isn't
    # factored for testability.

    activity.reboot_needed = None
    activity._register_reboot_for_units()
    assert not activity.reboot_needed

    # The method is ignorant to the state before, so it doesn't change what's
    # already there.
    activity.reboot_needed = RebootType.WARM
    activity._register_reboot_for_units()
    assert activity.reboot_needed == RebootType.WARM

    # But we do explicitly set the reboot type in the case that a unit
    # needs a reboot.
    activity.reboot_needed = None
    activity.unit_changes = {
        "restart": ["mnt-nfs-shared.mount"],
        "start": [],
        "reload": [],
        "stop": [],
    }
    activity._register_reboot_for_units()
    assert activity.reboot_needed == RebootType.WARM
    assert activity.summary == textwrap.dedent(
        """\
        System update: 21.05.1233.a9cc58d -> 21.05.1235.bacc11d

        Will reboot after the update.

        Restart: mnt-nfs-shared.mount

        Environment: fc-21.05-production (unchanged)
        Build number: 93111 -> 93222
        Channel URL: https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz"""
    )
    assert log.has("changed-units-require-reboot", units="mnt-nfs-shared.mount")


def test_update_release_change_reboot_required(
    log, logger, tmp_path, activity, nixos_mock, monkeypatch
):
    # I'd rather like to call prepare() here but the overall logic isn't
    # factored for testability.

    activity.reboot_needed = None
    activity._register_reboot_for_release_change()
    assert not activity.reboot_needed

    # The method is ignorant to the state before, so it doesn't change what's
    # already there.
    activity.reboot_needed = RebootType.WARM
    activity._register_reboot_for_release_change()
    assert activity.reboot_needed == RebootType.WARM

    # We do not require a reboot if the release path contains only
    # a single (current) version
    activity.reboot_needed = None
    nixos_mock.CURRENT_VERSION_ID = "24.11"
    nixos_mock.NEXT_VERSION_ID = "24.11"
    activity._log_current_state()
    activity._detect_next_version()
    assert activity.release_path() == ["24.11"]
    activity._register_reboot_for_release_change()
    assert not activity.reboot_needed

    # We do not require a reboot if the release path contains only
    # a single (current) version
    activity.reboot_needed = None
    nixos_mock.CURRENT_VERSION_ID = "24.11"
    nixos_mock.NEXT_VERSION_ID = "25.05"
    nixos_mock.CURRENT_BUILD_ID = "24.11.abcde.12345"
    nixos_mock.NEXT_BUILD_ID = "25.05.edcba.54321"
    activity._log_current_state()
    activity._detect_next_version()
    assert activity.release_path() == ["24.11", "25.05"]
    activity._register_reboot_for_release_change()
    assert activity.reboot_needed == RebootType.WARM

    assert activity.summary == textwrap.dedent(
        """\
        System update: 24.11.abcde.12345 -> 25.05.edcba.54321
        
        Will reboot after the update.
        
        Start/Stop: postgresql
        Restart: telegraf
        Reload: nginx
        
        Environment: fc-21.05-production (unchanged)
        Build number: 93111 -> 93222
        Channel URL: https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz"""
    )
    assert log.has(
        "distro-release-change-require-reboot",
        current_release="24.11",
        next_release="25.05",
    )


def test_update_activity_run(
    log, nixos_mock, activity, logger, mock_resolve_url_redirects
):
    activity.run()

    assert activity.returncode == 0
    nixos_mock.update_system_channel.assert_called_with(
        activity.next_channel_url, log=activity.log
    )
    nixos_mock.build.assert_called_with(
        Channel(activity.log, activity.next_channel_url), log=activity.log
    )
    nixos_mock.register_system_profile.assert_called_with(
        NEXT_SYSTEM_PATH, log=activity.log
    )
    nixos_mock.switch_to_system.assert_called_with(
        NEXT_SYSTEM_PATH, lazy=False, switch_type="switch", log=activity.log
    )
    assert log.has("update-run-succeeded")


def test_update_activity_run_unchanged(log, nixos_mock, activity):
    # Mock nixos.current_system() to return the same as next_system
    nixos_mock.current_system.return_value = activity.next_system

    activity.run()

    nixos_mock.update_system_channel.assert_called_with(
        activity.next_channel_url, log=activity.log
    )
    nixos_mock.build.assert_not_called()

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


def test_update_activity_build_system_fails(
    log, nixos_mock, activity, mock_resolve_url_redirects
):
    nixos_mock.build.side_effect = BuildFailed(
        msg="msg", stdout="stdout", stderr="stderr"
    )

    activity.run()

    assert activity.returncode == 2
    assert log.has("update-run-error", returncode=2)


def test_update_activity_register_system_profile_fails(
    log, nixos_mock, activity, mock_resolve_url_redirects
):
    nixos_mock.register_system_profile.side_effect = RegisterFailed(
        msg="msg", stdout="stdout", stderr="stderr"
    )

    activity.run()

    assert activity.returncode == 3
    assert log.has("update-run-error", returncode=3)


def test_update_activity_switch_to_system_fails(
    log, nixos_mock, activity, mock_resolve_url_redirects
):
    nixos_mock.switch_to_system.side_effect = SwitchFailed(stdout="stdout")

    activity.run()

    assert activity.returncode == state.EXIT_TEMPFAIL
    assert log.has("update-run-tempfail", returncode=state.EXIT_TEMPFAIL)


def test_update_activity_switch_if_no_release_change(
    log, nixos_mock, activity, mock_resolve_url_redirects
):
    nixos_mock.os_release.return_value = {
        "BUILD_ID": "24.11.1111",
        "VERSION_ID": "24.11",
    }
    activity.next_version = "24.11.9999"
    activity.run()

    nixos_mock.switch_to_system.assert_called_once_with(
        NEXT_SYSTEM_PATH,
        lazy=False,
        switch_type="switch",
        log=activity.log,
    )


def test_update_activity_boot_if_release_change(
    log, nixos_mock, activity, mock_resolve_url_redirects
):
    nixos_mock.CURRENT_VERSION_ID = "24.11"
    nixos_mock.NEXT_VERSION_ID = "25.05"
    nixos_mock.CURRENT_BUILD_ID = "24.11.abcde.12345"
    nixos_mock.NEXT_BUILD_ID = "25.05.edcba.54321"

    activity._log_current_state()
    activity._detect_next_version()
    activity.run()

    nixos_mock.switch_to_system.assert_called_once_with(
        NEXT_SYSTEM_PATH,
        lazy=False,
        switch_type="boot",
        log=activity.log,
    )


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


def test_update_activity_with_nullable_nixos_properties(
    nixos_mock, activity, mock_resolve_url_redirects
):
    """Set all potentially nullable mocked properties to None and ensure this does not
    cause crashes"""
    nixos_mock.current_fc_environment_name.return_value = None
    nixos_mock.get_fc_channel_build = (
        fc.util.nixos.get_fc_channel_build
    )  # un-mock, this function has no side effects
    nixos_mock.os_release.return_value = {}
    nixos_mock.current_nixos_channel_url.return_value = None
    nixos_mock.current_system.return_value = None

    activity._log_current_state()
    activity._detect_next_version()
    activity.summary
    activity.run()


def test_current_properties_return_expected_values(nixos_mock, activity):
    """Test that current_* properties return values from nixos functions."""

    # Mock the nixos functions to return specific values
    nixos_mock.current_nixos_channel_url.return_value = (
        "https://hydra.flyingcircus.io/build/93111/download/1/nixexprs.tar.xz"
    )
    nixos_mock.current_fc_environment_name.return_value = "fc-21.05-production"
    nixos_mock.os_release.return_value = {
        "BUILD_ID": "21.05.1233.a9cc58d",
        "VERSION_ID": "21.05",
    }
    nixos_mock.system_kernel = Mock()
    nixos_mock.system_kernel.return_value = KernelIdentifier(
        "yshd-mocktest-5.10.42"
    )

    # Test that properties return the mocked values
    assert (
        activity.current_channel_url
        == "https://hydra.flyingcircus.io/build/93111/download/1/nixexprs.tar.xz"
    )
    assert activity.current_environment == "fc-21.05-production"
    assert activity.current_version == "21.05.1233.a9cc58d"
    assert str(activity.current_kernel) == "<Kernel: mocktest v5.10.42>"


def test_current_properties_not_serialized(activity):
    """Test that current_* properties are not included in serialized state."""
    state = activity.__getstate__()

    # None of the current_* properties should be in the serialized state,
    # they're supposed to be read from the live system
    assert "current_channel_url" not in state
    assert "current_environment" not in state
    assert "current_version" not in state
    assert "current_kernel" not in state
    assert "current_os_release" not in state


def test_update_from_enc_no_enc(log, logger):
    activity = UpdateActivity.from_enc(logger, {})
    assert activity is None
    assert log.has("enc-data-missing")


def test_update_from_enc_incompatible_with_local_channel(log, logger):
    """Given an unchanged channel url, should not prepare an update activity"""
    enc = {
        "parameters": {
            "environment_url": "file://test",
            "environment": "dev-checkout-24.05",
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


def test_update_should_run_on_resume(activity, monkeypatch):
    run_mock = Mock()
    monkeypatch.setattr(activity, "run", run_mock)
    activity.resume()
    assert run_mock.called
