"""Scheduled machine reboot.

This activity does nothing if the machine has been booted for another reason in
the time between creation and execution.
"""

from typing import Union

import structlog

from ..estimate import Estimate
from . import Activity, ActivityMergeResult, RebootType

_log = structlog.get_logger()


class RebootActivity(Activity):
    estimate = Estimate("5m")

    def __init__(
        self, action: Union[str, RebootType] = RebootType.WARM, log=_log
    ):
        super().__init__()
        self.set_up_logging(log)
        self.reboot_needed = RebootType(action)

    @property
    def comment(self):
        return "Scheduled {}".format(
            "cold boot" if self.reboot_needed == RebootType.COLD else "reboot"
        )

    def merge(self, other):
        if not isinstance(other, RebootActivity):
            self.log.debug(
                "merge-incompatible-skip",
                self_type=type(self),
                other_type=type(other),
            )
            return ActivityMergeResult()

        if self.reboot_needed == other.reboot_needed:
            self.log.debug("merge-reboot-identical")
            return ActivityMergeResult(self, is_effective=True)

        if (
            self.reboot_needed == RebootType.COLD
            and other.reboot_needed == RebootType.WARM
        ):
            self.log.debug(
                "merge-reboot-cold-warm",
                help=(
                    "merging a warm reboot into a cold reboot results in a "
                    "cold reboot."
                ),
            )
            return ActivityMergeResult(self, is_effective=True)

        if (
            self.reboot_needed == RebootType.WARM
            and other.reboot_needed == RebootType.COLD
        ):
            self.log.debug(
                "merge-reboot-warm-to-cold",
                help=(
                    "merging a cold reboot into a warm reboot results in a "
                    "cold reboot. This is a significant change."
                ),
            )
            return ActivityMergeResult(
                self,
                is_effective=True,
                is_significant=True,
                changes={"before": RebootType.WARM, "after": RebootType.COLD},
            )
