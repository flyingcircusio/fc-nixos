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
            fc.ceph.main.main(args)
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
            fc.ceph.main.main([subc])
        std = capsys.readouterr()
        output = std.out if std.out else std.err
        # message shall start be a short usage overview, including the subcommand
        assert output.startswith(f"usage: {progname} {subc}")
    # for invalid subsystem, show error message
    with pytest.raises(SystemExit):
        fc.ceph.main.main(["monInvalidSubc"])
    std = capsys.readouterr()
    assert f"{progname}: error: invalid choice" in std.err
