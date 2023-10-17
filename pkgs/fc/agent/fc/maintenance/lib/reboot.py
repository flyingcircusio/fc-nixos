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
