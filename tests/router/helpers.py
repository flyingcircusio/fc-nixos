import re
import time
from functools import cached_property
from pathlib import Path

import rich


class Router:
    def __init__(self, machine, verbose=True):
        self.machine = machine
        self.rich = rich
        self.verbose = verbose

    def inspect_machine(*a, **k):
        if self.verbose:
            rich.inspect(self.machine)

    @cached_property
    def initial_system_path(self):
        vm_script = Path(self.machine.script).read_text()
        return Path(
            re.search(
                "(/nix/store/.*-nixos-system.*)/kernel ", vm_script
            ).group(1)
        )

    @cached_property
    def secondary_system(self):
        print("secondary system:", self.initial_system_path)
        return self.initial_system_path

    @cached_property
    def primary_system(self):
        primary_system = (
            self.secondary_system / "specialisation/primary"
        ).resolve()
        print("primary system:", primary_system)
        return primary_system

    def is_primary(self):
        machine = self.machine
        current_system_path = machine.execute(
            "readlink -f /run/current-system"
        )[1].strip()
        return current_system_path == self.primary_system

    def wait_until_is_primary(self):
        machine = self.machine
        for x in range(30):
            current_system = Path(
                machine.execute("readlink -f /run/current-system")[1].strip()
            )
            print(
                f"Waiting for router to become primary (specialisation primary), try {x}"
            )
            print(
                "Current specialisation:",
                machine.execute("cat /etc/specialisation")[1].strip()
                or "(base system)",
            )
            print("Current system_path:", current_system)
            if current_system == self.primary_system:
                machine.wait_for_unit("default.target")
                current_date = machine.execute("date")[1]
                print(
                    f"Running as primary (specialisation primary) at {current_date}"
                )
                return
            time.sleep(0.5)

    def wait_until_is_secondary(self):
        machine = self.machine
        for x in range(30):
            current_system = Path(
                machine.execute("readlink -f /run/current-system")[1].strip()
            )
            print(
                f"Waiting for router to become secondary (base system), try {x}"
            )
            print(
                "Current specialisation:",
                machine.execute("cat /etc/specialisation")[1].strip()
                or "(base system)",
            )
            print("Current system_path:", current_system)
            if current_system == self.secondary_system:
                machine.wait_for_unit("default.target")
                current_date = machine.execute("date")[1]
                print(f"Running as secondary (base system) at {current_date}")
                return
            time.sleep(0.5)


def r(self):
    if not hasattr(self, "_r"):
        self._r = Router(self)

    return self._r
