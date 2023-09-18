"""Do a platform update.

This activity does nothing if the machine already uses the new version.
"""

import os.path as p
from typing import Optional

import structlog
from fc.maintenance.estimate import Estimate
from fc.util import nixos
from fc.util.nixos import UnitChanges

from ...util.channel import Channel
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
        self, next_channel_url: str, next_environment: str = None, log=_log
    ):
        super().__init__()
        self.next_environment = next_environment
        self.next_channel_url = next_channel_url
        self.changelog_url = None
        self.current_system = None
        self.next_system = None
        self.current_channel_url = None
        self.current_release = None
        self.next_release = None
        self.current_version = None
        self.next_version = None
        self.current_environment = None
        self.unit_changes: UnitChanges = {}
        self.current_kernel = None
        self.next_kernel = None
        self.reboot_needed = None
        self.set_up_logging(log)
        self._detect_current_state()
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
                "enc-data-missing", msg="No ENC data, cannot update the system."
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
        if self.current_system == self.next_system:
            return False
        return True

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

        try:
            self.next_system = nixos.build_system(
                self.next_channel_url, out_link=out_link, log=self.log
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

        self.unit_changes = nixos.dry_activate_system(
            self.next_system, self.log
        )

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
        if self.current_system == self.next_system:
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

    def run(self):
        """Do the update"""
        step = 1
        try:
            self.update_system_channel()

            if self.identical_to_current_system:
                self.returncode = 0
                return

            step = 2
            system_path = nixos.build_system(
                self.next_channel_url, log=self.log
            )
            step = 3
            nixos.register_system_profile(system_path, log=self.log)
            step = 4
            nixos.switch_to_system(system_path, lazy=False, log=self.log)
        except nixos.ChannelException as e:
            self.stdout = e.stdout
            self.stderr = e.stderr
            self.returncode = step
            self.log.error(
                "update-run-failed",
                _replace_msg="Update to {next_version} failed!",
                returncode=step,
                current_version=self.current_version,
                current_channel_url=self.current_channel_url,
                current_environment=self.current_environment,
                next_channel=self.next_channel_url,
                next_version=self.next_version,
                next_environment=self.next_environment,
                exc_info=True,
            )

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

        self.returncode = 0

    @property
    def summary(self):
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

        if self.next_release:
            msg.append(
                f"Release: {self.current_release} -> {self.next_release}"
            )
        if self.changelog_url:
            msg.append(f"ChangeLog: {self.changelog_url}")

        if self.current_environment != self.next_environment:
            msg.append(
                f"Environment: {self.current_environment} -> {self.next_environment}"
            )
        elif self.current_environment is not None:
            msg.append(f"Environment: {self.current_environment} (unchanged)")

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

    def _register_reboot_for_kernel(self):
        current_kernel = nixos.kernel_version(
            p.join(self.current_system, "kernel")
        )
        next_kernel = nixos.kernel_version(p.join(self.next_system, "kernel"))

        if current_kernel == next_kernel:
            self.log.debug("update-kernel-unchanged")
            self.reboot_needed = None
        else:
            self.log.info(
                "update-kernel-changed",
                current_kernel=current_kernel,
                next_kernel=next_kernel,
            )
            self.reboot_needed = RebootType.WARM

        self.current_kernel = current_kernel
        self.next_kernel = next_kernel

    def _detect_current_state(self):
        self.current_version = nixos.running_system_version(self.log)
        self.current_channel_url = nixos.current_nixos_channel_url()
        self.current_environment = nixos.current_fc_environment_name()
        self.current_system = nixos.current_system()
        self.log.debug(
            "update-activity-current-state",
            current_version=self.current_version,
            current_channel_url=self.current_channel_url,
            current_environment=self.current_environment,
            current_system=self.current_system,
        )

    def _detect_next_version(self):
        self.next_version = nixos.channel_version(self.next_channel_url)
