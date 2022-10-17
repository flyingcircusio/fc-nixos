"""Update NixOS system configuration from infrastructure or local sources."""

import os
import os.path as p
import re
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import fc.maintenance
import fc.util.logging
import requests
from fc.maintenance.lib.shellscript import ShellScriptActivity
from fc.util import nixos
from fc.util.enc import STATE_VERSION_FILE
from fc.util.nixos import RE_FC_CHANNEL

# nixos-rebuild doesn't support changing the result link name so we
# create a dir with a meaningful name (like /run/current-system) and
# let nixos-rebuild put it there.
# The link goes away after a reboot. It's possible that the new system
# will be garbage-collected before the switch in that case but the switch
# will still work.
NEXT_SYSTEM = "/run/next-system"

ACTIVATE = f"""\
set -e
nix-channel --add {{url}} nixos
nix-channel --update nixos
nix-channel --remove next
# Retry once in case nixos-build fails e.g. due to updates to Nix itself
nixos-rebuild switch || nixos-rebuild switch
rm -rf {NEXT_SYSTEM}
"""

os.environ["NIX_REMOTE"] = "daemon"


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


class Channel:

    PHRASES = re.compile(r"would (\w+) the following units: (.*)$")

    # global, to avoid re-connecting (with ssl handshake and all)
    session = requests.session()
    is_local = False

    def __init__(self, log, url, name="", environment=None, resolve_url=True):
        self.url = url
        self.name = name
        self.environment = environment
        self.system_path = None

        if url.startswith("file://"):
            self.is_local = True
            self.resolved_url = url.replace("file://", "")
        elif resolve_url:
            self.resolved_url = nixos.resolve_url_redirects(url)
        else:
            self.resolved_url = url

        self.log = log

        self.log_with_context = log.bind(
            url=self.resolved_url,
            name=name,
            environment=environment,
            is_local=self.is_local,
        )

    def version(self):
        if self.is_local:
            return "local-checkout"
        label_comp = [
            "/root/.nix-defexpr/channels/{}/{}".format(self.name, c)
            for c in [".version", ".version-suffix"]
        ]
        if all(p.exists(f) for f in label_comp):
            return "".join(open(f).read() for f in label_comp)

    def __str__(self):
        v = self.version() or "unknown"
        return "<Channel name={}, version={}, from={}>".format(
            self.name, v, self.resolved_url
        )

    def __eq__(self, other):
        if isinstance(other, Channel):
            return self.resolved_url == other.resolved_url
        return NotImplemented

    @classmethod
    def current(cls, log, channel_name):
        """Looks up existing channel by name.
        The URL found is usually already resolved (no redirects)
        so we don't do it again here. It can still be enabled with
        `resolve_url`, when needed.
        """
        if not p.exists("/root/.nix-channels"):
            log.debug("channel-current-no-nix-channels-dir")
            return
        with open("/root/.nix-channels") as f:
            for line in f.readlines():
                url, name = line.strip().split(" ", 1)
                if name == channel_name:
                    # We don't have to resolve the URL if it's a direct link
                    # to a Hydra build product. This is the normal case for
                    # running VMs because the nixos channel is set to an
                    # already resolved URL.
                    # Resolve all other URLs, for example initial URLs used
                    # during VM bootstrapping.
                    resolve_url = RE_FC_CHANNEL.match(url) is None
                    log.debug(
                        "channel-current",
                        url=url,
                        name=name,
                        resolve_url=resolve_url,
                    )
                    return Channel(log, url, name, resolve_url=resolve_url)

        log.debug("channel-current-not-found", name=name)

    def load_nixos(self):
        self.log_with_context.debug("channel-load-nixos")

        if self.is_local:
            raise RuntimeError("`load` not applicable for local channels")

        nixos.update_system_channel(self.resolved_url, self.log)

    def load_next(self):
        self.log_with_context.debug("channel-load-next")

        if self.is_local:
            raise RuntimeError("`load` not applicable for local channels")
        subprocess.run(
            ["nix-channel", "--add", self.resolved_url, "next"],
            check=True,
            capture_output=True,
            text=True,
        )
        subprocess.run(
            ["nix-channel", "--update", "next"],
            check=True,
            capture_output=True,
            text=True,
        )

    def check_local_channel(self):
        if not p.exists(p.join(self.resolved_url, "fc")):
            self.log_with_context.error(
                "local-channel-nix-path-invalid",
                _replace_msg="Expected NIX_PATH element 'fc' not found. Did you "
                "create a 'channels' directory via `dev-setup` and point "
                "the channel URL towards that directory?",
            )

    def switch(self, lazy=True, show_trace=False):
        """
        Build system with this channel and switch to it.
        Replicates the behaviour of nixos-rebuild switch and adds
        a "lazy mode" which only switches to the built system if it actually
        changed.
        """
        self.log_with_context.debug("channel-switch-start")
        # Put a temporary result link in /run to avoid a race condition
        # with the garbage collector which may remove the system we just built.
        # If register fails, we still hold a GC root until the next reboot.
        out_link = "/run/fc-agent-built-system"
        self.build(out_link, show_trace)
        nixos.register_system_profile(self.system_path, self.log)
        # New system is registered, delete the temporary result link.
        os.unlink(out_link)
        return nixos.switch_to_system(self.system_path, lazy, self.log)

    def build(self, out_link=None, show_trace=False):
        """
        Build system with this channel. Works like nixos-rebuild build.
        Does not modify the running system.
        """
        self.log_with_context.debug("channel-build-start")

        if show_trace:
            build_options = ["--show-trace"]
        else:
            build_options = []

        if self.is_local:
            self.check_local_channel()
        system_path = nixos.build_system(
            self.resolved_url, build_options, out_link, self.log
        )
        self.system_path = system_path

    def dry_activate(self):
        return nixos.dry_activate_system(self.system_path, self.log)

    def prepare_maintenance(self):
        self.log_with_context.debug("channel-prepare-maintenance-start")

        if not p.exists(NEXT_SYSTEM):
            os.mkdir(NEXT_SYSTEM)

        out_link = Path(NEXT_SYSTEM) / "result"
        self.system_path = nixos.build_system(
            "/root/.nix-defexpr/channels/next", out_link=out_link, log=self.log
        )
        changes = self.dry_activate()
        self.register_maintenance(changes)

    def register_maintenance(self, changes):
        self.log_with_context.debug("maintenance-register-start")

        def notify(category):
            services = changes.get(category, [])
            if services:
                return "{}: {}".format(
                    category.capitalize(),
                    ", ".join(s.replace(".service", "", 1) for s in services),
                )
            else:
                return ""

        notifications = list(
            filter(
                None,
                (notify(cat) for cat in ["stop", "restart", "start", "reload"]),
            )
        )
        msg_parts = [
            f"System update to {self.version()}",
            f"Environment: {self.environment}",
            f"Channel URL: {self.resolved_url}",
        ] + notifications

        current_kernel = nixos.kernel_version("/run/current-system/kernel")
        next_kernel = nixos.kernel_version("/run/next-system/result/kernel")

        if current_kernel != next_kernel:
            self.log.info(
                "maintenance-register-kernel-change",
                current_kernel=current_kernel,
                next_kernel=next_kernel,
            )
            msg_parts.append(
                "Will schedule a reboot to activate the changed kernel."
            )

        if len(msg_parts) > 1:  # add trailing newline if output is multi-line
            msg_parts += [""]

        msg = "\n".join(msg_parts)
        # XXX: We should use an fc-manage call (like --activate), instead of
        # Dumping the script into the maintenance request.
        script = ACTIVATE.format(url=self.resolved_url)
        self.log_with_context.debug(
            "maintenance-register-result", script=script, comment=msg
        )
        with fc.maintenance.ReqManager() as rm:
            rm.add(
                fc.maintenance.Request(
                    ShellScriptActivity(script), 600, comment=msg
                )
            )
        self.log.info("maintenance-register-succeeded")


class SwitchFailed(Exception):
    pass


@dataclass
class CheckResult:
    errors: list[str]
    warnings: list[str]

    def format_output(self) -> str:
        if self.errors:
            return "CRITICAL: " + " ".join(self.errors + self.warnings)

        if self.warnings:
            return "WARNING: " + " ".join(self.warnings)

        return "OK: no problems found."

    @property
    def exit_code(self) -> int:
        if self.errors:
            return 2

        if self.warnings:
            return 1

        return 0


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
                f"State version invalid: {state_version}, should look like 22.05"
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
        environment_url.startswith("file://") if environment_url else None
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

    return CheckResult(errors, warnings)


def prepare_switch_in_maintenance(log, enc):
    if not enc or not enc.get("parameters"):
        log.warning(
            "enc-data-missing", msg="No ENC data. Not building channel."
        )
        return False
    # scheduled update already present?
    if Channel.current(log, "next"):
        rm = fc.maintenance.ReqManager()
        rm.scan()
        if rm.requests:
            due = list(rm.requests.values())[0].next_due
            log.info(
                "maintenance-present",
                scheduled=bool(due),
                at=datetime.isoformat(due) if due else None,
            )
            return False

    # scheduled update available?
    next_channel = Channel(
        log,
        enc["parameters"]["environment_url"],
        name="next",
        environment=enc["parameters"]["environment"],
    )

    if not next_channel or next_channel.is_local:
        log.warn(
            "maintenance-error-local-channel",
            _replace_msg="Switch-in-maintenance incompatible with local checkout, abort.",
        )
        return False

    current_channel = Channel.current(log, "nixos")
    if next_channel != current_channel:
        next_channel.load_next()
        log.info(
            "maintenance-prepare-changed",
            current=str(current_channel),
            next=str(next_channel),
        )
        try:
            next_channel.prepare_maintenance()
        except nixos.ChannelException:
            subprocess.run(
                ["nix-channel", "--remove", "next"],
                check=True,
                capture_output=True,
                text=True,
            )
            raise

        return True
    else:
        log.info("maintenance-prepare-unchanged")
        return False


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
