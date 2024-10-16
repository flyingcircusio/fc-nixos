import contextlib
import json
import unittest.mock
from unittest.mock import MagicMock

import fc.maintenance.maintenance
from fc.maintenance import Request
from fc.maintenance.activity import RebootType
from fc.maintenance.activity.reboot import RebootActivity
from fc.maintenance.activity.update import UpdateActivity
from fc.maintenance.activity.vm_change import VMChangeActivity
from pytest import fixture

ENC = {
    "parameters": {
        "memory": 2048,
        "cores": 2,
    }
}


@fixture
def guest_properties(tmp_path):
    qemu_state_dir = tmp_path / "qemu"
    kvm_seed_dir = tmp_path / "fc-data"
    runtime_dir = tmp_path / "run"

    qemu_state_dir.mkdir(parents=True, exist_ok=True)
    kvm_seed_dir.mkdir(parents=True, exist_ok=True)
    runtime_dir.mkdir(parents=True, exist_ok=True)

    fc.maintenance.maintenance.QEMU_STATE_DIR = str(qemu_state_dir)
    fc.maintenance.maintenance.KVM_SEED_DIR = str(kvm_seed_dir)
    fc.maintenance.maintenance.RUNTIME_DIR = str(runtime_dir)

    return (qemu_state_dir, runtime_dir)


def write_properties_file(directory, filename, content):
    with open(directory / filename, "w") as f:
        if isinstance(content, dict):
            json.dump(content, f)
        else:
            f.write(content)


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


def test_request_reboot_for_qemu_binary_generation_change(
    logger, guest_properties
):
    qemu, run = guest_properties

    write_properties_file(qemu, "qemu-binary-generation-booted", "1")
    write_properties_file(run, "qemu-binary-generation-current", "2")

    request = fc.maintenance.maintenance.request_reboot_for_kvm_environment(
        logger
    )
    assert "Qemu binary environment has changed" in request.comment
    activity = request.activity
    assert isinstance(activity, RebootActivity)
    assert activity.reboot_needed == RebootType.COLD


def test_do_not_request_reboot_for_unchanged_qemu_binary_generation(
    logger, guest_properties
):
    qemu, run = guest_properties

    write_properties_file(qemu, "qemu-binary-generation-booted", "2")
    write_properties_file(run, "qemu-binary-generation-current", "2")

    request = fc.maintenance.maintenance.request_reboot_for_kvm_environment(
        logger
    )
    assert request is None


def test_do_not_request_reboot_for_downgraded_qemu_binary_generation(
    logger, guest_properties
):
    qemu, run = guest_properties

    write_properties_file(qemu, "qemu-binary-generation-booted", "2")
    write_properties_file(run, "qemu-binary-generation-current", "1")

    request = fc.maintenance.maintenance.request_reboot_for_kvm_environment(
        logger
    )
    assert request is None


def test_request_reboot_for_guest_properties_upgrade(logger, guest_properties):
    qemu, run = guest_properties

    write_properties_file(qemu, "qemu-binary-generation-booted", "2")
    write_properties_file(run, "qemu-binary-generation-current", "2")
    write_properties_file(
        run, "qemu-guest-properties-current", {"binary_generation": 2}
    )

    request = fc.maintenance.maintenance.request_reboot_for_kvm_environment(
        logger
    )
    assert "KVM environment has been updated" in request.comment
    activity = request.activity
    assert isinstance(activity, RebootActivity)
    assert activity.reboot_needed == RebootType.COLD


def test_request_reboot_for_guest_properties_qemu_change(
    logger, guest_properties
):
    qemu, run = guest_properties

    write_properties_file(
        qemu, "qemu-guest-properties-booted", {"binary_generation": 1}
    )
    write_properties_file(
        run, "qemu-guest-properties-current", {"binary_generation": 2}
    )

    request = fc.maintenance.maintenance.request_reboot_for_kvm_environment(
        logger
    )
    assert "Qemu binary environment has changed" in request.comment
    activity = request.activity
    assert isinstance(activity, RebootActivity)
    assert activity.reboot_needed == RebootType.COLD


def test_do_not_request_reboot_for_unchanged_guest_properties_qemu(
    logger, guest_properties
):
    qemu, run = guest_properties

    write_properties_file(
        qemu, "qemu-guest-properties-booted", {"binary_generation": 2}
    )
    write_properties_file(
        run, "qemu-guest-properties-current", {"binary_generation": 2}
    )

    request = fc.maintenance.maintenance.request_reboot_for_kvm_environment(
        logger
    )
    assert request is None


def test_do_not_request_reboot_for_downgraded_guest_properties_qemu(
    logger, guest_properties
):
    qemu, run = guest_properties

    write_properties_file(
        qemu, "qemu-guest-properties-booted", {"binary_generation": 2}
    )
    write_properties_file(
        run, "qemu-guest-properties-current", {"binary_generation": 1}
    )

    request = fc.maintenance.maintenance.request_reboot_for_kvm_environment(
        logger
    )
    assert request is None


def test_request_reboot_for_guest_property_new_property(
    logger, guest_properties
):
    qemu, run = guest_properties

    write_properties_file(
        qemu, "qemu-guest-properties-booted", {"binary_generation": 2}
    )
    write_properties_file(
        run,
        "qemu-guest-properties-current",
        {"binary_generation": 2, "cpu_model": "qemu64-v1"},
    )

    request = fc.maintenance.maintenance.request_reboot_for_kvm_environment(
        logger
    )
    assert "KVM parameters have changed" in request.comment
    assert "cpu_model (new parameter)" in request.comment
    activity = request.activity
    assert isinstance(activity, RebootActivity)
    assert activity.reboot_needed == RebootType.COLD


def test_do_not_request_reboot_for_guest_property_removed_property(
    logger, guest_properties
):
    qemu, run = guest_properties

    write_properties_file(
        qemu,
        "qemu-guest-properties-booted",
        {"binary_generation": 2, "cpu_model": "qemu64-v1"},
    )
    write_properties_file(
        run, "qemu-guest-properties-current", {"binary_generation": 2}
    )

    request = fc.maintenance.maintenance.request_reboot_for_kvm_environment(
        logger
    )
    assert request is None


def test_request_reboot_for_guest_property_value_change(
    logger, guest_properties
):
    qemu, run = guest_properties

    write_properties_file(
        qemu,
        "qemu-guest-properties-booted",
        {"binary_generation": 2, "cpu_model": "qemu64-v1"},
    )
    write_properties_file(
        run,
        "qemu-guest-properties-current",
        {"binary_generation": 2, "cpu_model": "Haswell-v4"},
    )

    request = fc.maintenance.maintenance.request_reboot_for_kvm_environment(
        logger
    )
    assert "KVM parameters have changed" in request.comment
    assert "cpu_model: qemu64-v1 -> Haswell-v4" in request.comment
    activity = request.activity
    assert isinstance(activity, RebootActivity)
    assert activity.reboot_needed == RebootType.COLD


def test_do_not_request_for_unchanged_guest_properties(
    logger, guest_properties
):
    qemu, run = guest_properties

    write_properties_file(
        qemu,
        "qemu-guest-properties-booted",
        {"binary_generation": 2, "cpu_model": "qemu64-v1"},
    )
    write_properties_file(
        run,
        "qemu-guest-properties-current",
        {"binary_generation": 2, "cpu_model": "qemu64-v1"},
    )

    request = fc.maintenance.maintenance.request_reboot_for_kvm_environment(
        logger
    )
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


def test_request_update(log, logger, agent_configparser, monkeypatch):
    from_enc_mock = MagicMock()
    from_enc_mock.return_value.identical_to_current_channel_url = False
    from_enc_mock.return_value.identical_to_current_system = False
    monkeypatch.setattr(
        "fc.maintenance.maintenance.UpdateActivity.from_enc", from_enc_mock
    )
    monkeypatch.setattr(
        "fc.util.nixos.get_free_store_disk_space", lambda *a: 10 * 1024**3
    )

    monkeypatch.setattr(
        "fc.util.nixos.system_closure_size", lambda *a: 2 * 1024**3
    )
    request = fc.maintenance.maintenance.request_update(
        logger, enc={}, config=agent_configparser, current_requests=[]
    )

    assert request
    assert log.has("request-update-prepared")


def test_request_update_unchanged(
    log, logger, agent_configparser, monkeypatch
):
    from_enc_mock = MagicMock()
    from_enc_mock.return_value = None
    monkeypatch.setattr(
        "fc.maintenance.maintenance.UpdateActivity.from_enc", from_enc_mock
    )

    request = fc.maintenance.maintenance.request_update(
        logger, enc={}, config=agent_configparser, current_requests=[]
    )

    assert request is None
    assert log.has("request-update-no-activity")


def test_request_update_unchanged_system_and_no_other_requests_skips_request(
    log, logger, agent_configparser, monkeypatch
):
    from_enc_mock = MagicMock()
    from_enc_mock.return_value.identical_to_current_channel_url = False
    from_enc_mock.return_value.identical_to_current_system = True
    monkeypatch.setattr(
        "fc.maintenance.maintenance.UpdateActivity.from_enc", from_enc_mock
    )

    monkeypatch.setattr(
        "fc.util.nixos.get_free_store_disk_space", lambda *a: 10 * 1024**3
    )

    monkeypatch.setattr(
        "fc.util.nixos.system_closure_size", lambda *a: 2 * 1024**3
    )
    request = fc.maintenance.maintenance.request_update(
        logger, enc={}, config=agent_configparser, current_requests=[]
    )

    assert request is None
    assert log.has("request-update-shortcut")


class FakeUpdateActivity(UpdateActivity):
    def _detect_current_state(self):
        pass

    def _detect_next_version(self):
        pass


def test_request_update_unchanged_system_and_other_requests_produces_request(
    log, logger, agent_configparser, monkeypatch
):
    from_enc_mock = MagicMock()
    from_enc_mock.return_value.identical_to_current_system = True
    monkeypatch.setattr(
        "fc.maintenance.maintenance.UpdateActivity.from_enc", from_enc_mock
    )

    monkeypatch.setattr(
        "fc.util.nixos.get_free_store_disk_space", lambda *a: 10 * 1024**3
    )

    monkeypatch.setattr(
        "fc.util.nixos.system_closure_size", lambda *a: 2 * 1024**3
    )
    existing_request = Request(FakeUpdateActivity("https://fake"))

    request = fc.maintenance.maintenance.request_update(
        logger,
        enc={},
        config=agent_configparser,
        current_requests=[existing_request],
    )

    assert request


def test_request_update_equivalent_existing_request_skip_request(
    log, logger, agent_configparser, monkeypatch
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
        config=agent_configparser,
        current_requests=[existing_request],
    )

    assert request is None
    assert log.has(
        "request-update-found-equivalent",
        request=existing_request.id,
        channel_url="https://fake",
    )


def test_request_update_skip_when_free_disk_low(
    log, logger, agent_configparser, monkeypatch
):
    from_enc_mock = MagicMock()
    from_enc_mock.return_value.identical_to_current_channel_url = False
    from_enc_mock.return_value.identical_to_current_system = False
    monkeypatch.setattr(
        "fc.maintenance.maintenance.UpdateActivity.from_enc", from_enc_mock
    )
    monkeypatch.setattr(
        "fc.util.nixos.get_free_store_disk_space", lambda *a: 6 * 1024**3
    )

    monkeypatch.setattr(
        "fc.util.nixos.system_closure_size", lambda *a: 2 * 1024**3
    )
    request = fc.maintenance.maintenance.request_update(
        logger, enc={}, config=agent_configparser, current_requests=[]
    )

    assert request is None
    assert log.has("request-update-low-free-disk")


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
