"""Update NixOS system configuration from infrastructure or local sources."""

import os
import re
import socket
import subprocess
from configparser import ConfigParser
from pathlib import Path

from fc.util import nixos
from fc.util.channel import Channel
from fc.util.checks import CheckResult
from fc.util.enc import STATE_VERSION_FILE
from fc.util.lock import locked
from fc.util.nixos import NIX_EVAL_WARNINGS_FILE, Specialisation

# Other platform code can also check the presence of this marker file to
# change behaviour before/during the first agent run.
INITIAL_RUN_MARKER = Path("/etc/nixos/fc_agent_initial_run")

MESSAGE_NO_FC_CHANNEL = """\
nixos channel URL does not point to a resolved FC channel build:
{channel}
This should not happen in normal operation and requires manual intervention by \
switching to a resolved channel URL, in the form:
https://hydra.flyingcircus.io/build/123456/download/1/nixexprs.tar.xz
Running `fc-manage switch -ce` should fix the issue.
"""

MESSAGE_NO_FC_CHANNEL_DEV = """\
nixos channel URL does not point to a resolved FC channel build:
{channel}
This is not critical as the system uses an environment pointing to a local dev
checkout for building the system but other Nix commands may fail.
The nixos channel should be set to a resolved channel URL, in the form:
https://hydra.flyingcircus.io/build/123456/download/1/nixexprs.tar.xz
Choosing a regular environment and running `fc-manage switch -ce` should fix
the issue.
"""


class SwitchFailed(Exception):
    pass


def check(
    log, enc, config: ConfigParser, eval_warnings_file=NIX_EVAL_WARNINGS_FILE
) -> CheckResult:
    errors = []
    warnings = []
    ok_info = []
    if INITIAL_RUN_MARKER.exists():
        warnings.append(
            f"{INITIAL_RUN_MARKER} exists. Looks like the agent has not "
            f"run successfully, yet."
        )

    system_version = nixos.os_release()["BUILD_ID"]

    if system_version:
        ok_info.append(f"System version: {system_version}.")
    else:
        warnings.append("Could not get version of running system.")

    if STATE_VERSION_FILE.exists():
        state_version = STATE_VERSION_FILE.read_text().strip()
        log.debug("check-state-version", state_version=state_version)
        # From NixOS 25.05 on this check becomes superfluous, as a malformed
        # state version causes an evaluation error in the system build.
        # Keeping this around for a transitory period.
        if re.fullmatch(r"\d\d\.\d\d", state_version):
            ok_info.append(f"State version: {state_version}.")
        else:
            warnings.append(
                f"State version invalid: {state_version}, should look like 24.05"
            )
    else:
        warnings.append(f"State version file {STATE_VERSION_FILE} missing.")

    # ENC data checks
    enc_params = enc["parameters"]

    environment_url = enc_params.get("environment_url")
    production_flag = enc_params.get("production")

    log.debug(
        "check-enc",
        environment_url=environment_url,
        production_flag=production_flag,
    )

    if production_flag is None:
        errors.append("ENC: production flag is missing.")

    if environment_url is None:
        errors.append("ENC: environment URL is missing.")

    uses_local_checkout = (
        environment_url.startswith("file:") if environment_url else None
    )

    if production_flag and uses_local_checkout:
        warnings.append("production VM uses local dev checkout.")

    # nixos channel checks (missing/malformed)
    nixos_channel = nixos.current_nixos_channel_url(log=log)
    if nixos_channel:
        build = nixos.get_fc_channel_build(nixos_channel, log)
        log.debug(
            "check-nixos-channel", nixos_channel=nixos_channel, build=build
        )
        if build is None:
            # There's something wrong with the nixos channel URL, we could not
            # get a build number from it.
            if INITIAL_RUN_MARKER.exists():
                # This is expected on the first agent run, no need to warn.
                pass
            elif uses_local_checkout:
                # Problematic, but not critical if a local dev checkout is used.
                warnings.append(
                    MESSAGE_NO_FC_CHANNEL_DEV.format(channel=nixos_channel)
                )
            else:
                # Intervention required or system may not build properly.
                errors.append(
                    MESSAGE_NO_FC_CHANNEL.format(channel=nixos_channel)
                )
    else:
        errors.append("`nixos` channel not set.")

    if eval_warnings_file.exists():
        nixos_warnings_content = eval_warnings_file.read_text()
        if nixos_warnings_content:
            nixos_warnings = [
                warning
                for w in nixos_warnings_content.split("\n\n")
                if (warning := w.strip())
            ]
            warnings.append(f"NixOS warnings found ({len(nixos_warnings)})")
            warnings.extend(nixos_warnings)

    try:
        system_size = nixos.system_closure_size(
            log, Path("/run/current-system")
        )
    except Exception:
        warnings.append("Failed to get closure size of current system.")
    else:
        free_disk_gib = nixos.get_free_store_disk_space(log) / 1024**3
        disk_keep_free = config.getfloat(
            "limits", "disk_keep_free", fallback=5.0
        )
        size_gib = system_size / 1024**3
        free_space_error_thresh = size_gib + disk_keep_free
        free_space_warning_thresh = size_gib * 2 + disk_keep_free

        if free_disk_gib < free_space_error_thresh:
            errors.append(
                "Not enough free disk space to build a new system. "
                f"Free: {free_disk_gib:.1f} GiB. "
                f"Required: {free_space_error_thresh:.1f} GiB "
                f"({size_gib:.1f} system size + {disk_keep_free:.1f}). "
                "Automated updates are suspended until more space is available."
            )
        elif free_disk_gib < free_space_warning_thresh:
            warnings.append(
                f"Free disk space is getting low. "
                f"Free: {free_disk_gib:.1f} GiB. "
                f"Required: {free_space_error_thresh:.1f} GiB "
                f"({size_gib:.1f} system size + {disk_keep_free:.1f}). "
                "Building a new system could fail if more disk space is used."
            )
        else:
            ok_info.append(f"System size: {size_gib:.1f} GiB.")

    return CheckResult(errors, warnings, ok_info)


def dry_activate(log, channel_url, show_trace=False):
    channel = Channel(
        log,
        channel_url,
    )
    return nixos.dry_activate_channel(
        channel=channel, show_trace=show_trace, log=log
    )


def initial_switch_if_needed(log, enc, lock_dir) -> bool:
    if not INITIAL_RUN_MARKER.exists():
        return False

    log = log.bind(init_stage=1)

    try:
        name = enc["name"]
        reported_hostname = socket.gethostname()
        log.debug(
            "fc-manage-init-set-hostname",
            enc_hostname=name,
            reported_hostname=reported_hostname,
        )
        subprocess.check_call(["/run/current-system/sw/bin/hostname", name])
    except Exception:
        log.warn(
            "fc-manage-init-hostname-failed",
            _replace_msg="Couldn't set hostname during initial build.",
            exc_info=True,
        )

    log.info(
        "fc-manage-initial-build",
        _replace_msg=(
            "Building minimal system without roles using the initial "
            "channel (stage 1), SSH access should work after this finishes."
        ),
    )
    try:
        nixos.switch(specialisation="", log=log, lock_dir=lock_dir, lazy=False)
    except Exception:
        log.warning(
            "fc-manage-initial-build-failed",
            _replace_msg=(
                "Initial build failed (stage 1), but we can still continue and "
                "try with the requested channel URL."
            ),
            exc_info=True,
        )
    else:
        log.info(
            "fc-manage-initial-build-succeeded",
            _replace_msg="Initial build finished (stage 1).",
        )

    log = log.bind(init_stage=2)

    log.info(
        "fc-manage-initial-channel-update",
        _replace_msg=(
            "Updating to requested channel URL, but still without roles "
            "(stage 2)."
        ),
    )

    # The NixOS configuration also checks INITIAL_RUN_MARKER. As it's still
    # present, the system will build without roles.
    switch(
        log,
        enc,
        Specialisation.BASE_CONFIG,
        lock_dir,
        update_channel=True,
        lazy=True,
    )

    INITIAL_RUN_MARKER.unlink()
    log.info(
        "fc-manage-initial-channel-update-succeeded",
        _replace_msg=(
            "Initial channel update and switch succeeded, removed initial "
            "agent run marker at {initial_agent_run_marker}."
        ),
        initial_agent_run_marker=INITIAL_RUN_MARKER,
    )

    return True


def switch(
    log,
    enc,
    specialisation: str | Specialisation,
    lock_dir: Path,
    update_channel: bool,
    lazy=False,
    show_trace=False,
    switch_reboot=False,
) -> bool:
    """Rebuild the system and switch to it.
    For regular operation, the current "nixos" channel is used for building the
    system. ENC data can specify a different channel URL.
    If the URL points to a local checkout, it is used for building instead.
    """
    channel_url = enc.get("parameters", {}).get("environment_url")
    environment = enc.get("parameters", {}).get("environment")
    current_channel = Channel.current(log, "nixos")

    # When nixos.switch recieves None as channel, the current one on the system gets used.
    channel_to_build = None

    if channel_url:
        channel_from_url = Channel(
            log,
            channel_url,
            name="nixos",
            environment=environment,
        )

        if channel_from_url.is_local:
            log.info(
                "fc-manage-local-checkout",
                _replace_msg=(
                    "Using local nixpkgs checkout at {checkout_path}, from "
                    "environment {environment}."
                ),
                checkout_path=channel_from_url.resolved_url,
                environment=environment,
            )
            channel_to_build = channel_from_url
        elif update_channel:
            log.info(
                "fc-manage-rebuild-with-update",
                _replace_msg=(
                    "Updating system, environment {environment}, "
                    "channel {channel}"
                ),
                environment=environment,
                channel=channel_url,
            )
            channel_to_build = channel_from_url
    else:
        log.warning(
            "fc-manage-no-channel-url",
            _replace_msg=(
                "Couldn't find a channel URL in ENC data. Continuing with the "
                "cached system channel."
            ),
        )

    if switch_reboot:
        intended_switch_type = "boot"
    else:
        intended_switch_type = "switch"

    return nixos.switch(
        channel=channel_to_build,
        specialisation=specialisation,
        lock_dir=lock_dir,
        lazy=lazy,
        show_trace=show_trace,
        intended_switch_type=intended_switch_type,
        log=log,
    )


def switch_to_configuration(
    log,
    specialisation: str | Specialisation,
    lock_dir: Path,
    lazy=False,
) -> None:
    """Switch to an already existing system, by default the current system.
    This can be used to switch to a different specialisation, switch back from a
    specialisation to the base system or just run the system activation again for
    the already active system.
    """

    system_path = Path("/nix/var/nix/profiles/system").resolve()
    nixos.switch_to_configuration(
        system_path, specialisation, lock_dir, lazy, intended_switch_type="test"
    )
