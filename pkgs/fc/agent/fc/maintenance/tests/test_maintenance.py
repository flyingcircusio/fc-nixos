import contextlib
import unittest.mock
from unittest.mock import MagicMock

import fc.maintenance.maintenance
from fc.maintenance import Request
from fc.maintenance.activity import RebootType
from fc.maintenance.activity.reboot import RebootActivity
from fc.maintenance.activity.update import UpdateActivity
from fc.maintenance.activity.vm_change import VMChangeActivity

ENC = {
    "parameters": {
        "memory": 2048,
        "cores": 2,
    }
}


@unittest.mock.patch("fc.util.dmi_memory.main")
@unittest.mock.patch("fc.util.vm.count_cores")
def test_request_reboot_for_memory(count_cores, get_memory, logger):
    get_memory.return_value = 1024
    request = fc.maintenance.maintenance.request_reboot_for_memory(logger, ENC)
    assert "1024 MiB -> 2048" in request.comment
    activity = request.activity
    assert isinstance(activity, VMChangeActivity)
    activity.set_up_logging(logger)
    activity.run()
    assert activity.reboot_needed == RebootType.COLD


@unittest.mock.patch("fc.util.dmi_memory.main")
@unittest.mock.patch("fc.util.vm.count_cores")
def test_do_not_request_reboot_for_unchanged_memory(
    count_cores, get_memory, logger
):
    get_memory.return_value = 2048
    request = fc.maintenance.maintenance.request_reboot_for_memory(logger, ENC)
    assert request is None


@unittest.mock.patch("fc.util.dmi_memory.main")
@unittest.mock.patch("fc.util.vm.count_cores")
def test_request_reboot_for_cpu(count_cores, get_memory, logger):
    count_cores.return_value = 1
    request = fc.maintenance.maintenance.request_reboot_for_cpu(logger, ENC)
    assert "1 -> 2" in request.comment
    activity = request.activity
    assert isinstance(activity, VMChangeActivity)
    activity.set_up_logging(logger)
    activity.run()
    assert activity.reboot_needed == RebootType.COLD


@unittest.mock.patch("fc.util.dmi_memory.main")
@unittest.mock.patch("fc.util.vm.count_cores")
def test_do_not_request_reboot_for_unchanged_cpu(
    count_cores, get_memory, logger
):
    count_cores.return_value = 2
    request = fc.maintenance.maintenance.request_reboot_for_cpu(logger, ENC)
    assert request is None


@unittest.mock.patch("os.path.isdir")
@unittest.mock.patch("os.path.exists")
@unittest.mock.patch("shutil.move")
def test_request_reboot_for_qemu_change(
    shutil_move,
    path_exists,
    path_isdir,
    logger,
):
    path_isdir.return_value = True
    path_exists.return_value = True

    def fake_open_qemu_files(filename, encoding):
        mock = unittest.mock.Mock()
        if filename == "/run/qemu-binary-generation-current":
            mock.read.return_value = "2"
        elif filename == "/var/lib/qemu/qemu-binary-generation-booted":
            mock.read.return_value = "1"

        yield mock

    with unittest.mock.patch(
        "builtins.open", contextlib.contextmanager(fake_open_qemu_files)
    ):
        request = fc.maintenance.maintenance.request_reboot_for_qemu(logger)

    assert "Qemu binary environment has changed" in request.comment
    activity = request.activity
    assert isinstance(activity, RebootActivity)
    assert activity.reboot_needed == RebootType.COLD


@unittest.mock.patch("os.path.isdir")
@unittest.mock.patch("os.path.exists")
@unittest.mock.patch("shutil.move")
def test_do_not_request_reboot_for_unchanged_qemu(
    shutil_move,
    path_exists,
    path_isdir,
    logger,
):
    path_isdir.return_value = True
    path_exists.return_value = True

    def fake_open_qemu_files(filename, encoding):
        mock = unittest.mock.Mock()
        if filename == "/run/qemu-binary-generation-current":
            mock.read.return_value = "1"
        elif filename == "/var/lib/qemu/qemu-binary-generation-booted":
            mock.read.return_value = "1"

        yield mock

    with unittest.mock.patch(
        "builtins.open", contextlib.contextmanager(fake_open_qemu_files)
    ):
        request = fc.maintenance.maintenance.request_reboot_for_qemu(logger)

    assert request is None


def test_request_reboot_for_kernel_change(logger):
    def fake_changed_kernel_version(path):
        if path == "/run/booted-system/kernel":
            return "5.10.45"
        elif path == "/run/current-system/kernel":
            return "5.10.50"

    with unittest.mock.patch(
        "fc.util.nixos.kernel_version", fake_changed_kernel_version
    ):
        request = fc.maintenance.maintenance.request_reboot_for_kernel(
            logger, []
        )

    assert "kernel (5.10.45 to 5.10.50)" in request.comment
    activity = request.activity
    assert isinstance(activity, RebootActivity)
    assert activity.reboot_needed == RebootType.WARM


def test_do_not_request_reboot_for_unchanged_kernel(logger):
    def fake_changed_kernel_version(path):
        if path == "/run/booted-system/kernel":
            return "5.10.50"
        elif path == "/run/current-system/kernel":
            return "5.10.50"

    with unittest.mock.patch(
        "fc.util.nixos.kernel_version", fake_changed_kernel_version
    ):
        request = fc.maintenance.maintenance.request_reboot_for_kernel(
            logger, []
        )

    assert request is None


def test_request_update(log, logger, monkeypatch):
    enc = {}
    from_enc_mock = MagicMock()
    from_enc_mock.return_value.identical_to_current_channel_url = False
    from_enc_mock.return_value.identical_to_current_system = False
    monkeypatch.setattr(
        "fc.maintenance.maintenance.UpdateActivity.from_enc", from_enc_mock
    )

    request = fc.maintenance.maintenance.request_update(logger, enc, [])

    assert request
    assert log.has("request-update-prepared")


def test_request_update_unchanged(log, logger, monkeypatch):
    from_enc_mock = MagicMock()
    from_enc_mock.return_value = None
    monkeypatch.setattr(
        "fc.maintenance.maintenance.UpdateActivity.from_enc", from_enc_mock
    )

    request = fc.maintenance.maintenance.request_update(
        logger,
        enc={},
        current_requests=[],
    )

    assert request is None
    assert log.has("request-update-no-activity")


def test_request_update_unchanged_system_and_no_other_requests_skips_request(
    log, logger, monkeypatch
):
    from_enc_mock = MagicMock()
    from_enc_mock.return_value.identical_to_current_channel_url = False
    from_enc_mock.return_value.identical_to_current_system = True
    monkeypatch.setattr(
        "fc.maintenance.maintenance.UpdateActivity.from_enc", from_enc_mock
    )

    request = fc.maintenance.maintenance.request_update(
        logger,
        enc={},
        current_requests=[],
    )

    assert request is None
    assert log.has("request-update-shortcut")


class FakeUpdateActivity(UpdateActivity):
    def _detect_current_state(self):
        pass

    def _detect_next_version(self):
        pass


def test_request_update_unchanged_system_and_other_requests_produces_request(
    log, logger, monkeypatch
):
    from_enc_mock = MagicMock()
    from_enc_mock.return_value.identical_to_current_system = True
    monkeypatch.setattr(
        "fc.maintenance.maintenance.UpdateActivity.from_enc", from_enc_mock
    )

    existing_request = Request(FakeUpdateActivity("https://fake"))

    request = fc.maintenance.maintenance.request_update(
        logger,
        enc={},
        current_requests=[existing_request],
    )

    assert request


def test_request_update_equivalent_existing_request_skip_request(
    log, logger, monkeypatch
):
    from_enc_mock = MagicMock()
    from_enc_mock.return_value.next_channel_url = "https://fake"
    monkeypatch.setattr(
        "fc.maintenance.maintenance.UpdateActivity.from_enc", from_enc_mock
    )

    existing_request = Request(FakeUpdateActivity("https://fake"))

    request = fc.maintenance.maintenance.request_update(
        logger,
        enc={},
        current_requests=[existing_request],
    )

    assert request is None
    assert log.has(
        "request-update-found-equivalent",
        request=existing_request.id,
        channel_url="https://fake",
    )


def test_do_not_request_reboot_when_tempfail_update_present(
    logger, log, monkeypatch
):
    with unittest.mock.patch("fc.util.nixos.kernel_version") as mock:
        activity = FakeUpdateActivity("https://fake")
        activity.reboot_needed = RebootType.WARM
        request = Request(activity)
        monkeypatch.setattr(Request, "tempfail", True)
        request = fc.maintenance.maintenance.request_reboot_for_kernel(
            logger, [request]
        )
        assert log.has("kernel-skip-update-tempfail")
        assert not mock.called

    assert request is None
