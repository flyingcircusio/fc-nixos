"""Update NixOS system configuration from infrastructure or local sources."""

import os
import re
import socket
import subprocess
from pathlib import Path

from fc.util import nixos
from fc.util.channel import Channel
from fc.util.checks import CheckResult
from fc.util.enc import STATE_VERSION_FILE

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


def check(log, enc) -> CheckResult:
    errors = []
    warnings = []
    if INITIAL_RUN_MARKER.exists():
        warnings.append(
            f"{INITIAL_RUN_MARKER} exists. Looks like the agent has not "
            f"run successfully, yet."
        )

    if STATE_VERSION_FILE.exists():
        state_version = STATE_VERSION_FILE.read_text().strip()
        log.debug("check-state-version", state_version=state_version)
        if not re.match(r"\d\d\.\d\d", state_version):
            warnings.append(
                f"State version invalid: {state_version}, should look like 23.11"
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
    nixos_channel = nixos.current_nixos_channel_url(log)
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

    nixos_warnings_file = Path("/etc/fcio_nixos_warnings")

    if nixos_warnings_file.exists():
        nixos_warnings_content = nixos_warnings_file.read_text()
        if nixos_warnings_content:
            nixos_warnings = [
                warning
                for w in nixos_warnings_content.split("\n\n")
                if (warning := w.strip())
            ]
            warnings.append(f"NixOS warnings found ({len(nixos_warnings)})")
            warnings.extend(nixos_warnings)

    return CheckResult(errors, warnings)


def dry_activate(log, channel_url, show_trace=False):
    channel = Channel(
        log,
        channel_url,
    )
    channel.build(show_trace=show_trace)
    return channel.dry_activate()


def initial_switch_if_needed(log, enc):
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
        out_link = "/run/fc-agent-built-system"
        system_path = nixos.build_system(out_link=out_link, log=log)
        nixos.register_system_profile(system_path, log)
        # New system is registered, delete the temporary result link.
        os.unlink(out_link)
        nixos.switch_to_system(system_path, lazy=False, log=log)
    except Exception:
        log.warn(
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
    switch_with_update(log, enc, lazy=True)

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
    lazy=False,
    show_trace=False,
):
    """Rebuild the system and switch to it.
    For regular operation, the current "nixos" channel is used for building the
    system. ENC data can specify a different channel URL.
    If the URL points to a local checkout, it is used for building instead.
    """
    channel_url = enc.get("parameters", {}).get("environment_url")
    environment = enc.get("parameters", {}).get("environment")

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
        else:
            channel_to_build = Channel.current(log, "nixos")
            if channel_to_build != channel_from_url:
                log.debug(
                    "fc-manage-update-available",
                    current_channel_url=channel_to_build.resolved_url,
                    new_channel_url=channel_from_url.resolved_url,
                    environment=environment,
                )
    else:
        log.warn(
            "fc-manage-no-channel-url",
            _replace_msg=(
                "Couldn't find a channel URL in ENC data. Continuing with the "
                "cached system channel."
            ),
        )

        channel_to_build = Channel.current(log, "nixos")

    if channel_to_build:
        return channel_to_build.switch(lazy, show_trace)


def switch_with_update(
    log,
    enc,
    lazy=False,
    show_trace=False,
):
    channel_url = enc.get("parameters", {}).get("environment_url")
    environment = enc.get("parameters", {}).get("environment")

    if channel_url:
        channel = Channel(
            log,
            channel_url,
            name="nixos",
            environment=environment,
        )
        # Update nixos channel if it's not a local checkout
        if channel.is_local:
            log.info(
                "channel-update-skip-local",
                _replace_msg=(
                    "Skip channel update because it doesn't make sense with "
                    "local dev checkouts."
                ),
            )
        else:
            log.info(
                "fc-manage-rebuild-with-update",
                _replace_msg=(
                    "Updating system, environment {environment}, "
                    "channel {channel}"
                ),
                environment=environment,
                channel=channel_url,
            )
            channel.load_nixos()
    else:
        channel = Channel.current(log, "nixos")

    if not channel:
        return

    return channel.switch(lazy, show_trace)
