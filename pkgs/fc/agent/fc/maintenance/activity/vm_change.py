"""Handle VM changes that need a cold reboot.
"""
from typing import Optional

import fc.util.dmi_memory
import fc.util.vm
import structlog

from ..estimate import Estimate
from . import Activity, ActivityMergeResult, RebootType

_log = structlog.get_logger()


class VMChangeActivity(Activity):
    def __init__(
        self,
        wanted_memory: Optional[int] = None,
        wanted_cores: Optional[int] = None,
        log=_log,
    ):
        super().__init__()
        self.set_up_logging(log)
        self.current_memory = None
        self.wanted_memory = wanted_memory
        self.current_cores = None
        self.wanted_cores = wanted_cores
        self.reboot_needed = None
        self.estimate = Estimate("5m")

    @property
    def comment(self):
        msgs = []

        if self.wanted_memory and self.current_memory != self.wanted_memory:
            msgs.append(
                f"Memory {self.current_memory} MiB -> "
                f"{self.wanted_memory} MiB."
            )

        if self.wanted_cores and self.current_cores != self.wanted_cores:
            msgs.append(
                f"CPU cores {self.current_cores} -> {self.wanted_cores}."
            )

        if msgs:
            return " ".join(["Reboot to activate VM changes:"] + msgs)

    @classmethod
    def from_system_if_changed(cls, wanted_memory=None, wanted_cores=None):
        activity = cls(wanted_memory, wanted_cores)
        activity.update_from_system_state()

        if activity.is_effective:
            return activity

    def update_from_system_state(self):
        self.current_memory = fc.util.dmi_memory.main()
        self.current_cores = fc.util.vm.count_cores()
        self._update_reboot_needed()

    def merge(self, other) -> ActivityMergeResult:
        if not isinstance(other, VMChangeActivity):
            self.log.debug(
                "merge-incompatible-skip",
                other_type=type(other).__name__,
            )
            return ActivityMergeResult()

        is_effective_before = self.is_effective
        changes = {}

        if other.wanted_memory != self.wanted_memory:
            self.log.debug(
                "vm-change-merge-memory-diff",
                this_memory=self.wanted_memory,
                other_memory=other.wanted_memory,
            )
            if other.wanted_memory:
                changes["memory"] = {
                    "before": self.wanted_memory,
                    "after": other.wanted_memory,
                }
                self.wanted_memory = other.wanted_memory

        if other.wanted_cores != self.wanted_cores:
            self.log.debug(
                "vm-change-merge-cores-diff",
                this_cores=self.wanted_cores,
                other_cores=other.wanted_cores,
            )
            if other.wanted_cores:
                changes["cores"] = {
                    "before": self.wanted_cores,
                    "after": other.wanted_cores,
                }
                self.wanted_cores = other.wanted_cores

        return ActivityMergeResult(
            self,
            is_effective=self.is_effective,
            is_significant=self.is_effective and not is_effective_before,
            changes=changes,
        )

    @property
    def is_effective(self):
        """Does this actually change anything?"""
        if self.wanted_memory and self.current_memory != self.wanted_memory:
            return True
        if self.wanted_cores and self.current_cores != self.wanted_cores:
            return True

        return False

    def _need_poweroff_for_memory(self):
        if self.wanted_memory is None:
            return False

        actual_memory = fc.util.dmi_memory.main()
        if self.current_memory != actual_memory:
            self.log.debug(
                "poweroff-mem-changed",
                msg="Memory changed after creation of this activity.",
                expected_current_memory=self.current_memory,
                actual_memory=actual_memory,
            )

        if actual_memory == self.wanted_memory:
            self.log.debug(
                "poweroff-mem-noop",
                msg="Memory already at wanted value, no power-off needed.",
                actual_memory=actual_memory,
            )
            return False
        else:
            self.log.debug(
                "poweroff-mem-needed",
                msg="Power-off needed to activate new memory size.",
                actual_memory=actual_memory,
                wanted_memory=self.wanted_memory,
            )
            return True

    def _need_poweroff_for_cores(self):
        if self.wanted_cores is None:
            return False

        actual_cores = fc.util.vm.count_cores()
        if self.current_cores != actual_cores:
            self.log.debug(
                "poweroff-cores-changed",
                msg="Cores changed after creation of this activity.",
                expected_current_cores=self.current_cores,
                actual_cores=actual_cores,
            )

        if actual_cores == self.wanted_cores:
            self.log.debug(
                "poweroff-cores-noop",
                msg="Cores already at wanted value, no power-off needed.",
                actual_cores=actual_cores,
            )
            return False
        else:
            self.log.debug(
                "poweroff-cores-needed",
                msg="Power-off needed to activate new cores count.",
                actual_cores=actual_cores,
                wanted_cores=self.wanted_cores,
            )
            return True

    def _update_reboot_needed(self):
        if self._need_poweroff_for_memory() or self._need_poweroff_for_cores():
            self.reboot_needed = RebootType.COLD
        else:
            self.reboot_needed = None

    def run(self):
        self._update_reboot_needed()
        self.returncode = 0

    def resume(self):
        # run() just checks if the reboot is needed at the moment so we can safely
        # retry this activity.
        self.run()
