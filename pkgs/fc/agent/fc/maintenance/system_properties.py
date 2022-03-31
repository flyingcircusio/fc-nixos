import os.path
import shutil

import fc.util
import fc.util.dmi_memory
import fc.util.nixos
import fc.util.vm
import structlog
from fc.maintenance.lib.reboot import RebootActivity

log = structlog.get_logger()


def request_reboot_for_memory(enc):
    """Schedules reboot if the memory size has changed."""
    wanted_memory = int(enc["parameters"].get("memory", 0))
    if not wanted_memory:
        return
    current_memory = fc.util.dmi_memory.main()
    if current_memory == wanted_memory:
        return
    msg = f"Reboot to change memory from {current_memory} MiB to {wanted_memory} MiB"
    log.info(
        "memory-change",
        _replace_msg=f"Scheduling reboot to activate memory change: {current_memory} -> {wanted_memory}",
        current_memory=current_memory,
        wanted_memory=wanted_memory,
    )
    return fc.maintenance.Request(RebootActivity("poweroff"), 600, comment=msg)


def request_reboot_for_cpu(enc):
    """Schedules reboot if the number of cores has changed."""
    wanted_cores = int(enc["parameters"].get("cores", 0))
    if not wanted_cores:
        return
    current_cores = fc.util.vm.count_cores()
    if current_cores == wanted_cores:
        return
    msg = f"Reboot to change CPU count from {current_cores} to {wanted_cores}"
    log.info(
        "cpu-change",
        _replace_msg=f"Scheduling reboot to activate cpu change: {current_cores} -> {wanted_cores}",
        current_cores=current_cores,
        wanted_cores=wanted_cores,
    )
    return fc.maintenance.Request(RebootActivity("poweroff"), 600, comment=msg)


def request_reboot_for_qemu():
    """Schedules a reboot if the Qemu binary environment has changed."""
    # Update the -booted marker if necessary. We need to store the marker
    # in a place where it does not get removed after _internal_ reboots
    # of the virtual machine. However, if we got rebooted with a fresh
    # Qemu instance, we need to update it from the marker on the tmp
    # partition.
    if not os.path.isdir("/var/lib/qemu"):
        os.makedirs("/var/lib/qemu")
    if os.path.exists("/tmp/fc-data/qemu-binary-generation-booted"):
        shutil.move(
            "/tmp/fc-data/qemu-binary-generation-booted",
            "/var/lib/qemu/qemu-binary-generation-booted",
        )
    # Schedule maintenance if the current marker differs from booted
    # marker.
    if not os.path.exists("/run/qemu-binary-generation-current"):
        return

    try:
        with open("/run/qemu-binary-generation-current", encoding="ascii") as f:
            current_generation = int(f.read().strip())
    except Exception:
        # Do not perform maintenance if no current marker is there.
        return

    try:
        with open(
            "/var/lib/qemu/qemu-binary-generation-booted", encoding="ascii"
        ) as f:
            booted_generation = int(f.read().strip())
    except Exception:
        # Assume 0 as the generation marker as that is our upgrade path:
        # VMs started with an earlier version of fc.qemu will not have
        # this marker at all.
        booted_generation = 0

    if booted_generation >= current_generation:
        # We do not automatically downgrade. If we ever want that then I
        # want us to reconsider the side-effects.
        return

    msg = "Cold restart because the Qemu binary environment has changed"
    return fc.maintenance.Request(RebootActivity("poweroff"), 600, comment=msg)


def request_reboot_for_kernel():
    """Schedules a reboot if the kernel has changed."""
    booted = fc.util.nixos.kernel_version("/run/booted-system/kernel")
    current = fc.util.nixos.kernel_version("/run/current-system/kernel")
    log.debug("check-kernel-reboot", booted=booted, current=current)
    if booted != current:
        log.info(
            "kernel-changed",
            _replace_msg="Scheduling reboot to activate new kernel {booted} -> {current}",
            booted=booted,
            current=current,
        )
        return fc.maintenance.Request(
            RebootActivity("reboot"),
            600,
            comment=f"Reboot to activate changed kernel ({booted} to {current})",
        )
