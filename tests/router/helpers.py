import sys
from pathlib import Path

rich_path = "${pkgs.python38Packages.rich}/lib/python3.8/site-packages/"
sys.path.append(rich_path)

import rich


def pp(*a, **k):
    if VERBOSE:
        rich.print(*a, **k)


def is_primary(machine):
    system_path = machine.execute("readlink -f /run/current-system")[1].strip()
    return system_path == primary_system


def wait_until_is_primary(machine):
    while 1:
        current_system = Path(
            machine.execute("readlink -f /run/current-system")[1].strip()
        )
        print(
            "current specialisation:",
            machine.execute("cat /etc/specialisation")[1],
        )
        print("current system_path:", current_system)
        if current_system == primary_system:
            machine.wait_for_unit("default.target")
            return
        time.sleep(0.5)


def wait_until_is_secondary(machine):
    while 1:
        current_system = Path(
            machine.execute("readlink -f /run/current-system")[1].strip()
        )
        print(
            "current specialisation:",
            machine.execute("cat /etc/specialisation")[1],
        )
        print("current system_path:", current_system)
        if current_system == secondary_system:
            machine.wait_for_unit("default.target")
            return
        time.sleep(0.5)
