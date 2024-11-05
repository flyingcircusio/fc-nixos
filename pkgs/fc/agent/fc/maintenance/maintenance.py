"""
Create maintenance activities and a wrapping request object based on current
system state. All maintenance activities start their life here in this module.

TODO: better logging for created activites.

"""

import json
import os.path
import shutil
import typing
from pathlib import Path
from typing import Iterable, Optional

import fc.util
import fc.util.dmi_memory
import fc.util.nixos
import fc.util.vm
from fc.maintenance import Request
from fc.maintenance.activity import RebootType
from fc.maintenance.activity.reboot import RebootActivity
from fc.maintenance.activity.update import UpdateActivity
from fc.maintenance.activity.vm_change import VMChangeActivity
from fc.maintenance.state import State
from fc.util import nixos

QEMU_STATE_DIR = "/var/lib/qemu"
KVM_SEED_DIR = "/tmp/fc-data"
RUNTIME_DIR = "/run"


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


def request_reboot_for_kvm_environment(log) -> Optional[Request]:
    """Schedules a reboot if the hypervisor environment has changed."""
    # Update the -booted marker if necessary. We need to store the
    # marker in a place where it does not get removed after warm
    # reboots of the virtual machine (i.e. same Qemu process on the
    # KVM host). However, if we get a cold reboot (i.e. fresh Qemu
    # process) then we need to update it from the marker seeded on the
    # tmp partition.
    log.debug("request-reboot-for-kvm-environment-start")

    qemu_state_dir = Path(QEMU_STATE_DIR)

    cold_state_file = lambda stem: Path(KVM_SEED_DIR) / f"qemu-{stem}-booted"
    warm_state_file = lambda stem: qemu_state_dir / f"qemu-{stem}-booted"
    running_state_file = (
        lambda stem: Path(RUNTIME_DIR) / f"qemu-{stem}-current"
    )

    if not qemu_state_dir.is_dir():
        qemu_state_dir.mkdir(parents=True)

    # Newer versions of fc.qemu can signal multiple relevant guest
    # properties in a single file. Older versions will only signal the
    # boot-time qemu binary generation.
    if cold_state_file("guest-properties").exists():
        shutil.move(
            cold_state_file("guest-properties"),
            warm_state_file("guest-properties"),
        )
        cold_state_file("binary-generation").unlink(missing_ok=True)
    elif cold_state_file("binary-generation").exists():
        shutil.move(
            cold_state_file("binary-generation"),
            warm_state_file("binary-generation"),
        )

    # Optimistically load combined guest properties files
    try:
        with open(running_state_file("guest-properties")) as f:
            current_properties = json.load(f)
    except FileNotFoundError:
        current_properties = None
    except Exception:
        current_properties = {}

    # If the combined properties do not exist then fall back to the
    # old binary generation file.
    if current_properties is None:
        try:
            with open(
                running_state_file("binary-generation"), encoding="ascii"
            ) as f:
                current_generation = int(f.read().strip())
        except Exception:
            current_generation = None

        try:
            with open(
                warm_state_file("binary-generation"), encoding="ascii"
            ) as f:
                booted_generation = int(f.read().strip())
        except Exception:
            # Assume 0 as the generation marker as that is our upgrade
            # path: VMs started with an earlier version of fc.qemu
            # will not have this marker at all
            booted_generation = 0

        if (
            current_generation is not None
            and current_generation > booted_generation
        ):
            msg = (
                "Cold restart because the Qemu binary environment has changed"
            )
            return Request(RebootActivity("poweroff"), comment=msg)

        return

    # If the combined properties file exists but could not be decoded,
    # then ignore it. Note that we always expect at least the binary
    # generation to be provided in the combined file.
    if not current_properties:
        return

    try:
        with open(warm_state_file("guest-properties")) as f:
            booted_properties = json.load(f)
    except Exception:
        booted_properties = None

    # If the boot-time properties file does not exist, or does not
    # have valid content, then we should reboot and re-run the seeding
    # process from the start. This covers the case we were booted on a
    # hypervisor which did not provide guest properties which has
    # since been upgraded to start providing them, and it also handles
    # the case where a bug on the hypervisor has delivered us invalid
    # data, in which case we reboot optimistically in the hopes that
    # the hypervisor has since been fixed.
    if not booted_properties:
        msg = "Cold restart because the KVM environment has been updated"
        return Request(RebootActivity("poweroff"), comment=msg)

    # Special handling for the binary generation, which should ignore
    # downgrades.
    current_generation = current_properties.pop("binary_generation", None)
    booted_generation = booted_properties.pop("binary_generation", 0)

    if (
        current_generation is not None
        and current_generation > booted_generation
    ):
        msg = "Cold restart because the Qemu binary environment has changed"
        return Request(RebootActivity("poweroff"), comment=msg)

    fragments = []
    # Keys which are present at boot time but no longer at runtime are
    # implicitly ignored here.
    for key in current_properties.keys():
        # New keys which were not present at boot but were introduced
        # at runtime should cause a reboot.
        if key not in booted_properties:
            fragments.append(f"{key} (new parameter)")

        # Changes in values between boot and runtime should cause a
        # reboot.
        elif booted_properties[key] != current_properties[key]:
            fragments.append(
                "{}: {} -> {}".format(
                    key, booted_properties[key], current_properties[key]
                )
            )

    if fragments:
        msg = "Cold restart because KVM parameters have changed: {}".format(
            ", ".join(fragments)
        )
        return Request(RebootActivity("poweroff"), comment=msg)


def request_reboot_for_kernel(
    log, current_requests: Iterable[Request]
) -> Optional[Request]:
    """Schedules a reboot if the kernel has changed."""

    tempfail_update_requests_with_reboot = [
        req
        for req in current_requests
        if isinstance(req.activity, UpdateActivity)
        and req.tempfail
        and req.activity.reboot_needed == RebootType.WARM
    ]

    if tempfail_update_requests_with_reboot:
        log.info(
            "kernel-skip-update-tempfail",
            _replace_msg=(
                "Skipping the kernel version check as there is an update"
                "activity that wants a reboot but had a temporary failure."
                "The activity will be retried on the next agent run and "
                "trigger a reboot when it succeeds."
            ),
        )
        return

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


def request_update(
    log, enc, config, current_requests: Iterable[Request]
) -> Optional[Request]:
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

    if (
        not other_planned_requests
        and activity.identical_to_current_channel_url
    ):
        # Shortcut to save time preparing an activity which will have no effect.
        return

    free_disk_gib = nixos.get_free_store_disk_space(log) / 1024**3
    size_gib = (
        nixos.system_closure_size(log, Path("/run/current-system")) / 1024**3
    )
    disk_keep_free = config.getfloat("limits", "disk_keep_free", fallback=5.0)
    free_disk_thresh = size_gib + disk_keep_free

    if free_disk_gib < free_disk_thresh:
        log.error(
            "request-update-low-free-disk",
            _replace_msg=(
                "Not preparing the system update as free disk space is low. "
                f"Free: {free_disk_gib:.1f} GiB. "
                f"Required: {free_disk_thresh:.1f} GiB "
                f"({size_gib:.1f} system size + {disk_keep_free:.1f})."
            ),
        )
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
