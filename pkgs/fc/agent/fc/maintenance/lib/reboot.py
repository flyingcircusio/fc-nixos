import subprocess
import time

import fc.maintenance.activity.reboot
from fc.maintenance.activity import Activity, RebootType


class RebootActivity(fc.maintenance.activity.reboot.RebootActivity):
    """Load legacy reboot activities created with previous fc-agent versions."""

    coldboot: bool

    def load(self):
        # We only need to determine the reboot type on load. Everything
        # else works like the current RebootActivity.
        self.reboot_needed = (
            RebootType.COLD if self.coldboot else RebootType.WARM
        )

    def resume(self):
        self.log.info(
            "legacy-reboot-activity-noop",
            _replace_msg=(
                "Finalizing a legacy reboot activity which has been created by an "
                "earlier version of fc-agent and is still in 'running' state. "
                "Doing nothing as the reboot likely has already happened. "
            ),
        )
        self.reboot_needed = None
        self.returncode = 0
