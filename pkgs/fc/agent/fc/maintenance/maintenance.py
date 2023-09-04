"""
Create maintenance activities and a wrapping request object based on current
system state. All maintenance activities start their life here in this module.

TODO: better logging for created activites.

"""
import os.path
import shutil
from typing import Optional

import fc.util
import fc.util.dmi_memory
import fc.util.nixos
import fc.util.vm
from fc.maintenance import Request
from fc.maintenance.activity.reboot import RebootActivity
from fc.maintenance.activity.update import UpdateActivity
from fc.maintenance.activity.vm_change import VMChangeActivity


def request_reboot_for_memory(log, enc) -> Optional[Request]:
    """Schedules reboot if the memory size has changed."""
    wanted_memory = int(enc["parameters"].get("memory", 0))
    log.debug("request-reboot-for-memory", enc_memory=wanted_memory)

    if not wanted_memory:
        return

    activity = VMChangeActivity.from_system_if_changed(
        wanted_memory=wanted_memory
    )

    if activity:
        return Request(activity)


def request_reboot_for_cpu(log, enc) -> Optional[Request]:
    """Schedules reboot if the number of cores has changed."""
    wanted_cores = int(enc["parameters"].get("cores", 0))
    log.debug("request-reboot-for-cpu", enc_cores=wanted_cores)

    if not wanted_cores:
        return

    activity = VMChangeActivity.from_system_if_changed(
        wanted_cores=wanted_cores
    )

    if activity:
        return Request(activity)


def request_reboot_for_qemu(log) -> Optional[Request]:
    """Schedules a reboot if the Qemu binary environment has changed."""
    # Update the -booted marker if necessary. We need to store the marker
    # in a place where it does not get removed after _internal_ reboots
    # of the virtual machine. However, if we got rebooted with a fresh
    # Qemu instance, we need to update it from the marker on the tmp
    # partition.
    log.debug("request-reboot-for-qemu-start")
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
        # want us to reconsider the side effects.
        return

    msg = "Cold restart because the Qemu binary environment has changed"
    return Request(RebootActivity("poweroff"), comment=msg)


def request_reboot_for_kernel(log) -> Optional[Request]:
    """Schedules a reboot if the kernel has changed."""
    booted = fc.util.nixos.kernel_version("/run/booted-system/kernel")
    current = fc.util.nixos.kernel_version("/run/current-system/kernel")
    log.debug("check-kernel-reboot", booted=booted, current=current)
    if booted != current:
        log.info(
            "kernel-changed",
            _replace_msg=(
                "Scheduling reboot to activate new kernel {booted} -> {current}",
            ),
            booted=booted,
            current=current,
        )
        return Request(
            RebootActivity("reboot"),
            comment=f"Reboot to activate changed kernel ({booted} to {current})",
        )


def request_update(log, enc, current_requests) -> Optional[Request]:
    """Schedule a system update if the channel has changed and the
    resulting system is different from the running system.

    There are several shortcuts. The first one skip preparing the update
    altogether if the new channel URL is the same as the current channel of the system.
    This save preparing, thus building the system which is quite expensive to do.

    Also, if the preparation yields a system which is the same as the current one,
    we just switch to the new channel to save time and avoid announcing an update which
    is basically a no-op.
    """
    activity = UpdateActivity.from_enc(log, enc)

    if activity is None:
        log.debug("request-update-no-activity")
        return

    other_planned_requests = [
        req
        for req in current_requests
        if isinstance(req.activity, UpdateActivity)
    ]

    equivalent_planned_requests = [
        req
        for req in other_planned_requests
        if req.activity.next_channel_url == activity.next_channel_url
    ]

    if equivalent_planned_requests:
        log.info(
            "request-update-found-equivalent",
            _replace_msg=(
                "Existing request {request} with same channel URL: {channel_url}"
            ),
            request=equivalent_planned_requests[0].id,
            channel_url=activity.next_channel_url,
        )
        return

    if not other_planned_requests and activity.identical_to_current_channel_url:
        # Shortcut to save time preparing an activity which will have no effect.
        return

    activity.prepare()

    # Always request an update if other updates are planned at the moment. Adding
    # this activity can cancel out an existing activity by going back to the
    # current system state. This is useful when someone requests an update by error
    # and wants to undo it. Let the merge algorithm figure this out.
    if not other_planned_requests and activity.identical_to_current_system:
        log.info(
            "request-update-shortcut",
            _replace_msg=(
                "As there are no other update requests, skip the update and set the "
                "system channel directly."
            ),
        )
        activity.update_system_channel()
        return

    if not activity.identical_to_current_system:
        log.info(
            "request-update-prepared",
            _replace_msg=(
                "Update preparation was successful. This update will apply "
                "changes to the system."
            ),
            _output=activity.summary,
            current_channel=activity.current_channel_url,
            next_channel=activity.next_channel_url,
        )

    return Request(activity)
