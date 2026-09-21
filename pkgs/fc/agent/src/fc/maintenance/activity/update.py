"""Do a platform update.

This activity does nothing if the machine already uses the new version.
"""

import os.path as p
from pathlib import Path
from typing import Optional

import structlog

from fc.maintenance import state
from fc.maintenance.estimate import Estimate
from fc.util import nixos
from fc.util.logging import init_command_logging
from fc.util.nixos import UnitChanges

from ...util.channel import Channel
from ...util.lock import locked
from . import Activity, ActivityMergeResult, RebootType

_log = structlog.get_logger()

# The link goes away after a reboot. It's possible that the new system
# will be garbage-collected before the switch in that case but the switch
# will still work.
NEXT_SYSTEM = "/run/next-system"


class UpdateActivity(Activity):
    """
    Updates the NixOS system to a different channel URL.
    The new system resulting from the channel URL is already pre-built
    in `UpdateActivity.prepare` which means that a run of this activity usually
    only has to set the new system link and switch to it.
    """

    def __init__(
        self,
        next_channel_url: str,
        next_environment: str | None = None,
        log=_log,
    ):
        super().__init__()
        self.next_environment = next_environment
        self.next_channel_url = next_channel_url
        self.next_system = None
        self.next_version = None
        self.unit_changes: UnitChanges = {}
        self.next_kernel = None
        self.reboot_needed = None
        self.set_up_logging(log)
        self._log_current_state()
        self._detect_next_version()
        self.log.debug(
            "update-init",
            next_channel_url=next_channel_url,
            next_environment=next_environment,
        )

    def __eq__(self, other):
        return (
            isinstance(other, UpdateActivity)
            and self.__getstate__() == other.__getstate__()
        )

    @classmethod
    def from_enc(cls, log, enc) -> Optional["UpdateActivity"]:
        """
        Create a new UpdateActivity from ENC data or None, if nothing would
        change.

        """
        if not enc or not enc.get("parameters"):
            log.warning(
                "enc-data-missing",
                msg="No ENC data, cannot update the system.",
            )
            return

        env_name = enc["parameters"]["environment"]
        channel_url = enc["parameters"]["environment_url"]

        next_channel = Channel(
            log,
            channel_url,
            name="next",
            environment=env_name,
        )

        if next_channel.is_local:
            log.warn(
                "update-from-enc-local-channel",
                _replace_msg=(
                    "UpdateActivity is incompatible with local checkouts."
                ),
            )
            return

        activity = cls(next_channel.resolved_url, next_channel.environment)
        return activity

    @property
    def is_effective(self):
        """
        Predicts if the activity will make changes to the system based on current
        knowledge.
        This can change after preparing the update when the resulting system is known.
        We assume that channel URLs are immutable. No update when the URL is the same.
        An update producing the same system is also considered ineffective.

        Only comparing the systems could be misleading because system changes can
        be introduced by coincidental changes to local system configuration which should
        not trigger an update request (normal system builds with the current channel
        will pick it up).
        """
        if self.next_channel_url == self.current_channel_url:
            return False
        if nixos.current_system() == self.next_system:
            return False
        return True

    def load(self):
        # Add attributes after deserialization if needed to stay compatible
        # with older persisted instances of UpdateActivity.
        pass
        # there are currently no old pieces of activity data we need to stay compatible with

    def prepare(self, dry_run=False):
        self.log.debug(
            "update-prepare-start",
            current_version=self.current_version,
            current_channel_url=self.current_channel_url,
            current_environment=self.current_environment,
            next_channel=self.next_channel_url,
            next_environment=self.next_environment,
            dry_run=dry_run,
        )

        if dry_run:
            out_link = None
        else:
            out_link = NEXT_SYSTEM

        next_channel = Channel(self.log, self.next_channel_url)
        try:
            self.next_system = nixos.build(
                next_channel, out_link=out_link, log=self.log
            )
        except nixos.ChannelException:
            self.log.error(
                "update-prepare-build-failed",
                current_version=self.current_version,
                current_channel_url=self.current_channel_url,
                current_environment=self.current_environment,
                next_channel=self.next_channel_url,
                next_version=self.next_version,
                next_environment=self.next_environment,
            )
            raise

        # Note: These information might be stale in case the current_system has changed in the background between time of *prepare* and actual execution.
        self.unit_changes = nixos.dry_activate_system(
            self.next_system, self.log
        )

        self._register_reboot_for_release_change()
        self._register_reboot_for_units()
        self._register_reboot_for_kernel()

        if self.reboot_needed:
            self.estimate = Estimate("15m")
        elif (
            self.unit_changes["restart"]
            or self.unit_changes["stop"]
            or self.unit_changes["start"]
        ):
            self.estimate = Estimate("10m")
        else:
            # Only reloads or no unit changes, this should not take long
            self.estimate = Estimate("5m")

    def update_system_channel(self):
        nixos.update_system_channel(self.next_channel_url, self.log)

    @property
    def identical_to_current_channel_url(self) -> bool:
        if self.current_channel_url == self.next_channel_url:
            self.log.info(
                "update-identical-channel",
                channel=self.next_channel_url,
                _replace_msg=(
                    "Current system already uses the wanted channel URL."
                ),
            )
            return True

        return False

    @property
    def identical_to_current_system(self) -> bool:
        if nixos.current_system() == self.next_system:
            self.log.info(
                "update-identical-system",
                version=self.next_version,
                system=self.next_system.removeprefix("/nix/store/"),
                _replace_msg=(
                    "Running system {system} is already the wanted system."
                ),
            )
            return True

        return False

    def _handle_channel_exception(
        self,
        exc: nixos.ChannelException,
    ):
        match exc:
            case nixos.ChannelUpdateFailed():
                returncode = 1
                event = "update-run-error"
                msg = (
                    "Update error: setting {next_channel} ({next_version}) "
                    "as system channel failed."
                )
            case nixos.BuildFailed():
                returncode = 2
                event = "update-run-error"
                msg = (
                    "Update error: building {next_channel} ({next_version}) "
                    "failed."
                )
            case nixos.RegisterFailed():
                returncode = 3
                event = "update-run-error"
                msg = (
                    "Update error: registering system {next_system} for "
                    "version {next_version} failed."
                )
            case nixos.SwitchFailed():
                returncode = state.EXIT_TEMPFAIL
                event = "update-run-tempfail"
                msg = (
                    "Temporary failure when switching to the new system, "
                    "trying again."
                )
            case _:
                return

        self.stdout = exc.stdout
        self.stderr = exc.stderr
        self.returncode = returncode
        self.log.error(
            event,
            _replace_msg=msg,
            returncode=self.returncode,
            current_version=self.current_version,
            current_channel_url=self.current_channel_url,
            current_system=nixos.current_system(),
            current_environment=self.current_environment,
            next_channel=self.next_channel_url,
            next_system=self.next_system,
            next_version=self.next_version,
            next_environment=self.next_environment,
        )

    def resume(self):
        """It's safe to resume an interrupted update, just run it again."""
        self.run()

    def run(self):
        """Do the update"""
        try:
            self.update_system_channel()

            if self.identical_to_current_system:
                # Nothing to do here, always a success.
                self.returncode = 0
                return

            init_command_logging(self.log)

            next_channel = Channel(self.log, self.next_channel_url)
            system_path = nixos.build(next_channel, log=self.log)
            # System path may have changed since preparing the system because of
            # configuration changes, so update it here.
            self.next_system = system_path
            nixos.register_system_profile(system_path, log=self.log)
            switch_type = "switch"
            if len(self.release_path()) > 1:
                switch_type = "boot"

            with locked(
                self.log, self.lock_dir, "switch_to_configuration.lock"
            ):
                nixos.switch_to_system(
                    system_path,
                    lazy=False,
                    switch_type=switch_type,
                    log=self.log,
                )

        except nixos.ChannelException as e:
            self._handle_channel_exception(e)
            return

        self.log.info(
            "update-run-succeeded",
            _replace_msg="Update to {next_version} succeeded.",
            current_version=self.current_version,
            current_channel_url=self.current_channel_url,
            current_environment=self.current_environment,
            next_channel=self.next_channel_url,
            next_version=self.next_version,
            next_environment=self.next_environment,
        )

        # No clean up of the command log file needed as we initialized
        # logging only after checking that the activity changes the system.

        self.returncode = 0

    @property
    def summary(self) -> str:
        """
        A human-readable summary of what will be changed by this update.
        Includes possible reboots, significant unit state changes (start, stop,
        restart) as well as changes of build number, environment (
        fc-22.11-staging, for example) and channel URL.
        """
        msg = [
            f"System update: {self.current_version} -> {self.next_version}",
            "",
        ]

        if self.reboot_needed:
            msg.append("Will reboot after the update.")
            msg.append("")

        unit_change_lines = nixos.format_unit_change_lines(self.unit_changes)

        if unit_change_lines:
            msg.extend(unit_change_lines)
            msg.append("")

        if self.current_environment != self.next_environment:
            msg.append(
                f"Environment: {self.current_environment} -> {self.next_environment}"
            )
        elif self.current_environment is not None:
            msg.append(f"Environment: {self.current_environment} (unchanged)")

        current_build = None
        if self.current_channel_url:
            current_build = nixos.get_fc_channel_build(
                self.current_channel_url, self.log
            )
        if current_build:
            next_build = nixos.get_fc_channel_build(
                self.next_channel_url, self.log
            )
            if next_build:
                msg.append(f"Build number: {current_build} -> {next_build}")

        msg.append(f"Channel URL: {self.next_channel_url}")
        return "\n".join(msg)

    @property
    def comment(self):
        return self.summary

    def merge(self, other: Activity) -> ActivityMergeResult:
        if not isinstance(other, UpdateActivity):
            self.log.debug(
                "merge-incompatible-skip",
                self_type=type(self),
                other_type=type(other),
            )
            return ActivityMergeResult()

        current_state = self.__getstate__()
        other_state = other.__getstate__()

        if other_state == current_state:
            self.log.debug("merge-update-identical")
            return ActivityMergeResult(self, self.is_effective)

        if other.next_channel_url != self.next_channel_url:
            self.log.debug(
                "merge-update-channel-diff",
                current=current_state,
                new=other_state,
            )
        else:
            self.log.debug(
                "merge-update-metadata-diff",
                current=current_state,
                new=other_state,
            )

        added_unit_changes = {}
        removed_unit_changes = {}

        for category, changes in self.unit_changes.items():
            other_changes = other.unit_changes[category]
            added = set(other_changes) - set(changes)

            if added:
                added_unit_changes[category] = added

            removed = set(changes) - set(other_changes)

            if removed:
                removed_unit_changes[category] = removed

        changes = {
            "added_unit_changes": added_unit_changes,
            "removed_unit_changes": removed_unit_changes,
        }

        # Additional starts, stops and restart of units are considered a
        # significant change of the activity. Reloads are harmless and can be
        # ignored.

        is_significant = bool(
            added_unit_changes.get("start")
            or added_unit_changes.get("stop")
            or added_unit_changes.get("restart")
        )

        merged = UpdateActivity(other.next_channel_url)
        merged.__dict__.update({**current_state, **other_state})

        return ActivityMergeResult(
            merged, merged.is_effective, is_significant, changes
        )

    def release_path(self):
        """Return the path of involved NixOS releases.
        Returns a single element if no upgrade/downgrade happening, e.g. ["24.05"]
        or more than one if there is a downgrade happening. e.g. ["24.05", "24.11"]
        The order reflects the before -> after progression.
        """
        result = [nixos.os_release(nixos.current_system())["VERSION_ID"]]
        next_release = nixos.os_release(self.next_system)["VERSION_ID"]
        if next_release not in result:
            result.append(next_release)
        return result

    def _register_reboot_for_release_change(self):
        if len(release_path := self.release_path()) > 1:
            self.log.info(
                "distro-release-change-require-reboot",
                current_release=release_path[0],
                next_release=release_path[1],
            )
            self.reboot_needed = RebootType.WARM

    def _register_reboot_for_units(self):
        reboot_on_unit_change = {"mnt-nfs-shared.mount"}
        changed = set().union(*self.unit_changes.values())
        changed = changed.intersection(reboot_on_unit_change)
        if changed:
            self.log.info(
                "changed-units-require-reboot",
                units=",".join(sorted(changed)),
            )
            self.reboot_needed = RebootType.WARM

    def _register_reboot_for_kernel(self):
        next_kernel = nixos.system_kernel(Path(self.next_system))

        if self.current_kernel == next_kernel:
            self.log.debug("update-kernel-unchanged")
        else:
            self.log.info(
                "update-kernel-changed",
                current_kernel=self.current_kernel,
                next_kernel=next_kernel,
            )
            self.reboot_needed = RebootType.WARM

        self.next_kernel = next_kernel

    def _log_current_state(self):
        self.log.debug(
            "update-activity-current-state",
            current_version=nixos.os_release()["BUILD_ID"],
            current_channel_url=nixos.current_nixos_channel_url(),
            current_environment=nixos.current_fc_environment_name(),
            current_system=nixos.current_system(),
        )

    @property
    def current_channel_url(self):
        return nixos.current_nixos_channel_url()

    @property
    def current_environment(self):
        return nixos.current_fc_environment_name()

    @property
    def current_version(self):
        return nixos.os_release()["BUILD_ID"]

    @property
    def current_kernel(self) -> nixos.KernelIdentifier:
        system = nixos.current_system()
        assert system, "No current system path"
        return nixos.system_kernel(Path(system))

    def _detect_next_version(self):
        self.next_version = nixos.channel_version(self.next_channel_url)
