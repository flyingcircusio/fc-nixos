"""Scheduled machine reboot.

This activity does nothing if the machine has been booted for another reason in
the time between creation and execution.
"""

import argparse
import subprocess
import time

from fc.util.logging import init_logging

from ..activity import Activity
from ..reqmanager import DEFAULT_DIR, ReqManager
from ..request import Request


class RebootActivity(Activity):
    def __init__(self, action="reboot"):
        assert action in ["reboot", "poweroff"]
        self.action = action
        self.coldboot = action == "poweroff"
        # small allowance for VM clock skew
        self.initial_boottime = self.boottime() + 1

    @staticmethod
    def boottime():
        with open("/proc/uptime") as f:
            uptime = float(f.read().split()[0])
        return time.time() - uptime

    def boom(self):
        with open("starttime", "w") as f:
            print(time.time(), file=f)
        if self.coldboot:
            subprocess.check_call(["poweroff"])
        else:
            subprocess.check_call(["reboot"])
        self.finish(
            "shutdown at {}".format(
                time.strftime(
                    "%Y-%m-%d %H:%M:%S UTC", time.gmtime(time.time() + 60)
                )
            )
        )
        self.request.save()
        time.sleep(120)  # `shutdown` waits 1min until kicking off action

    def finish(self, message):
        """Signal to ReqManager that we are done."""
        self.stdout = message
        self.returncode = 0

    def other_coldboot(self):
        """Checks if there is another pending cold boot.

        Given that there are two reboot requests, one warm reboot and a
        cold reboot, the warm reboot will trigger and update boottime.
        Thus, the following cold reboot will not be performed (boottime
        > initial_boottime). But some setups require that the cold
        reboot must win regardless of issue order (e.g. Qemu), so we
        must skip warm reboots if a cold reboot is present.

        Returns cold boot request on success.
        """
        try:
            for req in self.request.other_requests():
                if (
                    isinstance(req.activity, RebootActivity)
                    and req.activity.coldboot
                ):
                    return req
        except AttributeError:  # self.request has not been set
            pass
        return

    def run(self):
        if not self.coldboot:
            coldboot_req = self.other_coldboot()
            if coldboot_req:
                return self.finish(
                    "cold boot pending ({}), skipped".format(coldboot_req.id)
                )
        boottime = self.boottime()
        if not boottime > self.initial_boottime:
            self.boom()
            return
        try:
            with open("starttime") as f:
                started = float(f.read().strip())
                self.duration = time.time() - started
        except (IOError, ValueError):
            pass
        self.finish(
            "booted at {} UTC".format(time.asctime(time.gmtime(boottime)))
        )


def main():
    a = argparse.ArgumentParser(description=__doc__)
    a.add_argument(
        "-c",
        "--comment",
        metavar="TEXT",
        default=None,
        help="announce upcoming reboot with this message",
    )
    a.add_argument(
        "-p",
        "--poweroff",
        default=False,
        action="store_true",
        help="power off instead of reboot",
    )
    a.add_argument(
        "-d",
        "--spooldir",
        metavar="DIR",
        default=DEFAULT_DIR,
        help="request spool dir (default: %(default)s)",
    )
    a.add_argument("-v", "--verbose", action="store_true", default=False)
    args = a.parse_args()
    init_logging(args.verbose)

    action = "poweroff" if args.poweroff else "reboot"
    defaultcomment = "Scheduled {}".format(
        "cold boot" if args.poweroff else "reboot"
    )
    with ReqManager(spooldir=args.spooldir) as rm:
        rm.scan()
        rm.add(
            Request(
                RebootActivity(action),
                900 if args.poweroff else 600,
                args.comment if args.comment else defaultcomment,
            )
        )

    def __rich__(self):
        if self.coldboot:
            return "Cold reboot"
        else:
            return "Warm reboot"
