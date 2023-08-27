"""Do a platform update.

This activity does nothing if the machine already uses the new version.
"""

import os.path as p

import structlog
from fc.util import nixos

from . import Activity, RebootType

_log = structlog.get_logger()

# The link goes away after a reboot. It's possible that the new system
# will be garbage-collected before the switch in that case but the switch
# will still work.
NEXT_SYSTEM = "/run/next-system"


class UpdateActivity(Activity):
    def __init__(
        self, next_channel_url: str, next_environment: str = None, log=_log
    ):
        self.next_environment = next_environment
        self.next_channel_url = nixos.resolve_url_redirects(next_channel_url)
        self.current_system = None
        self.next_system = None
        self.current_channel_url = None
        self.current_version = None
        self.next_version = None
        self.current_environment = None
        self.unit_changes = None
        self.current_kernel = None
        self.next_kernel = None
        self.set_up_logging(log)
        self._detect_current_state()
        self._detect_next_version()

    def __eq__(self, other):
        return (
            isinstance(other, UpdateActivity)
            and self.__getstate__() == other.__getstate__()
        )

    @classmethod
    def from_system_if_changed(
        cls, next_channel_url: str, next_environment: str = None
    ):
        activity = cls(next_channel_url, next_environment)
        if activity.is_effective:
            return activity

    @property
    def is_effective(self):
        """Does this actually change anything?"""
        return self.next_channel_url != self.current_channel_url

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

        self.next_system = nixos.build_system(
            self.next_channel_url, out_link=out_link, log=self.log
        )
        self.unit_changes = nixos.dry_activate_system(
            self.next_system, self.log
        )

        self._register_reboot_for_kernel()

    def run(self):
        """Do the update"""
        try:
            step = 1
            nixos.update_system_channel(self.next_channel_url, self.log)

            if nixos.running_system_version(self.log) == self.next_version:
                self.log.info(
                    "update-run-skip",
                    current_version=self.next_version,
                    _replace_msg=(
                        "Running version is already the wanted version "
                        "{current_version}, skip update."
                    ),
                )
                self.returncode = 0
                return

            step = 2
            system_path = nixos.build_system(
                self.next_channel_url, log=self.log
            )
            step = 3
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
    def changelog(self):
        def notify(category):
            services = self.unit_changes.get(category, [])
            if services:
                return "{}: {}".format(
                    category.capitalize(),
                    ", ".join(s.replace(".service", "", 1) for s in services),
                )
            else:
                return ""

        unit_changes = list(
            filter(
                None,
                (notify(cat) for cat in ["stop", "restart", "start", "reload"]),
            )
        )

        msg = [f"System update: {self.current_version} -> {self.next_version}"]

        current_build = nixos.get_fc_channel_build(
            self.current_channel_url, self.log
        )
        if current_build:
            next_build = nixos.get_fc_channel_build(
                self.next_channel_url, self.log
            )
            if next_build:
                msg.append(f"Build number: {current_build} -> {next_build}")

        if self.current_environment != self.next_environment:
            msg.append(
                f"Environment: {self.current_environment} -> {self.next_environment}"
            )
        elif self.current_environment is not None:
            msg.append(f"Environment: {self.current_environment} (unchanged)")

        msg.append("")

        if self.reboot_needed:
            msg.append("Will reboot after the update.")

        if unit_changes:
            msg.extend(unit_changes)
            msg.append("")

        msg.append(f"Channel URL: {self.next_channel_url}")
        return "\n".join(msg)

    def merge(self, activity):
        pass

    def _register_reboot_for_kernel(self):
        current_kernel = nixos.kernel_version(
            p.join(self.current_system, "kernel")
        )
        next_kernel = nixos.kernel_version(p.join(self.next_system, "kernel"))

        if current_kernel == next_kernel:
            self.log.debug("update-kernel-unchanged")
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
            "update-activity-update-current-state",
            current_version=self.current_version,
            current_channel_url=self.current_channel_url,
            current_environment=self.current_environment,
            current_system=self.current_system,
        )

    def _detect_next_version(self):
        self.next_version = nixos.channel_version(self.next_channel_url)
