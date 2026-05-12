import os
import re
from pathlib import Path
from sys import argv

import fc.ceph.main
import pytest


def test_main(capsys):
    """A proper help text on the whole fc-ceph command is shown when providing "-h",
    "--help", or no argument at all
    """
    progname = Path(argv[0]).name
    calling_args = [[], ["-h"], ["--help"]]
    for args in calling_args:
        with pytest.raises(SystemExit):
            fc.ceph.main.ceph(args)
        std = capsys.readouterr()
        output = std.out if std.out else std.err
        # help message shall start with short usage overview
        assert output.startswith(f"usage: {progname}")
        # help message shall give detailed command description
        assert "positional arguments" in output


def test_main_subcommand_usage(capsys):
    """An overview of subcommand actions is shown when providing no action."""
    progname = Path(argv[0]).name
    subcommands = ["osd", "mon", "mgr", "keys", "logs", "maintenance"]
    for subc in subcommands:
        with pytest.raises(SystemExit):
            fc.ceph.main.ceph([subc])
        std = capsys.readouterr()
        output = std.out if std.out else std.err
        # message shall start be a short usage overview, including the subcommand
        assert output.startswith(f"usage: {progname} {subc}")
    # for invalid subsystem, show error message
    with pytest.raises(SystemExit):
        fc.ceph.main.ceph(["monInvalidSubc"])
    std = capsys.readouterr()
    assert "invalid choice: 'monInvalidSubc'" in std.err


def test_main_locks_memory(capsys):
    """All mapped memory regions are locked, except [vdso] and MAP_DROPPABLE regions."""
    # smaps header format: <addr_start>-<addr_end> <perms> <offset> <dev> <inode> [name]
    # e.g.: 75be8cb90000-75be8cb92000 r-xp 00000000 00:00 0  [vdso]
    smaps_header = re.compile(
        r"^[0-9a-f]+-[0-9a-f]+ \S+ \S+ \S+ \d+\s*(?P<path>.*)"
    )

    with pytest.raises(SystemExit):
        fc.ceph.main.ceph([])

    pid = os.getpid()
    path = None
    pss = locked = "0 kB"

    with open(f"/proc/{pid}/smaps") as f:
        for line in f:
            print(line)
            if mapping_header := smaps_header.match(line):
                # path is optional, e.g. for anonymous mappings, but even then
                # we take it as a string to signal we're in a segment now
                path = mapping_header.group("path").strip()
                pss = locked = "0 kB"
            assert path is not None, (
                "Invalid segment rollover - expected `path` to be set - missing segment header?"
            )
            if line.startswith("Pss:"):
                pss = line.split(":")[1].strip()
            elif line.startswith("Locked:"):
                locked = line.split(":")[1].strip()
            elif line.startswith("VmFlags:"):
                vm_flags = line.split()[1:]
                if "dp" in vm_flags:
                    pass
                    # "dp" means MAP_DROPPABLE: pages are dropped rather than paged out,
                    # and do not count as mlocked.
                elif path == "[vdso]":
                    # kernel-owned memory space is safe, too.
                    pass
                else:
                    assert pss == locked, (
                        f"{path!r}: pss={pss}, locked={locked}"
                    )
                path = None
