import re
import time
from functools import cached_property
from pathlib import Path

import rich


class Router:
    def __init__(self, machine, system_top_level: str, verbose=True):
        self.machine = machine
        self.rich = rich
        self.verbose = verbose
        self.system_top_level = Path(system_top_level)

    def inspect_machine(*a, **k):
        if self.verbose:
            rich.inspect(self.machine)

    @cached_property
    def secondary_system(self):
        # secondary systems are the default config of a router role, without specialisation
        print("secondary system:", self.system_top_level)
        return self.system_top_level

    @cached_property
    def primary_system(self):
        primary_system = (
            self.secondary_system / "specialisation/primary"
        ).resolve()
        print("primary system:", primary_system)
        return primary_system

    @property
    def current_system(self):
        machine = self.machine
        return Path(
            machine.execute("readlink -f /run/current-system")[1].strip()
        )

    @property
    def is_primary(self):
        return self.current_system == self.primary_system

    def wait_until_is_primary(self):
        machine = self.machine
        name = machine.name

        for x in range(60):
            current_system = Path(
                machine.execute("readlink -f /run/current-system")[1].strip()
            )
            print(
                f"Waiting for {name} to become primary (specialisation primary), try {x}"
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

        raise AssertionError(f"Router {name} did not become primary!")

    def wait_until_is_secondary(self):
        machine = self.machine
        name = machine.name

        for x in range(60):
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

        raise AssertionError(f"Router {name} did not become primary!")


def r(self):
    if not hasattr(self, "_r"):
        self._r = Router(self)

    return self._r
