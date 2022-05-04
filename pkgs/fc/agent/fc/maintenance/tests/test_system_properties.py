import contextlib
import unittest.mock

from fc.maintenance.lib.reboot import RebootActivity
from fc.maintenance.system_properties import (
    request_reboot_for_cpu,
    request_reboot_for_kernel,
    request_reboot_for_memory,
    request_reboot_for_qemu,
)

ENC = {
    "parameters": {
        "memory": 2048,
        "cores": 2,
    }
}


@unittest.mock.patch("fc.maintenance.system_properties.RebootActivity.boottime")
@unittest.mock.patch("fc.util.dmi_memory.main")
def test_request_reboot_for_memory(get_memory, boottime):
    get_memory.return_value = 1024
    request = request_reboot_for_memory(ENC)
    assert "from 1024 MiB to 2048" in request.comment
    activity = request.activity
    assert isinstance(activity, RebootActivity)
    assert activity.action == "poweroff"


@unittest.mock.patch("fc.util.dmi_memory.main")
def test_do_not_request_reboot_for_unchanged_memory(get_memory):
    get_memory.return_value = 2048
    request = request_reboot_for_memory(ENC)
    assert request is None


@unittest.mock.patch("fc.maintenance.system_properties.RebootActivity.boottime")
@unittest.mock.patch("fc.util.vm.count_cores")
def test_request_reboot_for_cpu(count_cores, boottime):
    count_cores.return_value = 1
    request = request_reboot_for_cpu(ENC)
    assert "from 1 to 2" in request.comment
    activity = request.activity
    assert isinstance(activity, RebootActivity)
    assert activity.action == "poweroff"


@unittest.mock.patch("fc.util.vm.count_cores")
def test_do_not_request_reboot_for_unchanged_cpu(count_cores):
    count_cores.return_value = 2
    request = request_reboot_for_cpu(ENC)
    assert request is None


@unittest.mock.patch("fc.maintenance.system_properties.RebootActivity.boottime")
@unittest.mock.patch("os.path.isdir")
@unittest.mock.patch("os.path.exists")
@unittest.mock.patch("shutil.move")
def test_request_reboot_for_qemu_change(
    shutil_move,
    path_exists,
    path_isdir,
    boottime,
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
        request = request_reboot_for_qemu()

    assert "Qemu binary environment has changed" in request.comment
    activity = request.activity
    assert isinstance(activity, RebootActivity)
    assert activity.action == "poweroff"


@unittest.mock.patch("os.path.isdir")
@unittest.mock.patch("os.path.exists")
@unittest.mock.patch("shutil.move")
def test_do_not_request_reboot_for_unchanged_qemu(
    shutil_move,
    path_exists,
    path_isdir,
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
        request = request_reboot_for_qemu()

    assert request is None


@unittest.mock.patch("fc.maintenance.system_properties.RebootActivity.boottime")
def test_request_reboot_for_kernel_change(boottime):
    def fake_changed_kernel_version(path):
        if path == "/run/booted-system/kernel":
            return "5.10.45"
        elif path == "/run/current-system/kernel":
            return "5.10.50"

    with unittest.mock.patch(
        "fc.util.nixos.kernel_version", fake_changed_kernel_version
    ):
        request = request_reboot_for_kernel()

    assert "kernel (5.10.45 to 5.10.50)" in request.comment
    activity = request.activity
    assert isinstance(activity, RebootActivity)
    assert activity.action == "reboot"


def test_do_not_request_reboot_for_unchanged_kernel():
    def fake_changed_kernel_version(path):
        if path == "/run/booted-system/kernel":
            return "5.10.50"
        elif path == "/run/current-system/kernel":
            return "5.10.50"

    with unittest.mock.patch(
        "fc.util.nixos.kernel_version", fake_changed_kernel_version
    ):
        request = request_reboot_for_kernel()

    assert request is None
