"""Create scheduled maintenance with a shell script activity.

The maintenance activity script can be given either on the command line
or as a separate file. In case that there is no shebang line in the
file, it is executed with /bin/sh.
"""

import argparse
import io
import os
import subprocess
import sys

from fc.util.logging import init_logging

from ..activity import Activity
from ..reqmanager import DEFAULT_DIR, ReqManager
from ..request import Request


class ShellScriptActivity(Activity):
    def __init__(self, script_fobj):
        self.script = script_fobj.read()

    def run(self):
        # assumes that we are in the request scratch directory
        with open("script", "w") as f:
            if not self.script.startswith("#!"):
                f.write("#!/bin/sh\n")
            f.write(self.script)
            os.fchmod(f.fileno(), 0o755)

        script = os.path.join(os.getcwd(), "script")
        p = subprocess.Popen(
            [script],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        (self.stdout, self.stderr) = [s.decode() for s in p.communicate()]
        self.returncode = p.returncode


def main():
    a = argparse.ArgumentParser(
        description=__doc__,
        epilog="""
If neither a script file or --exec is given, read the activity script from
stdin.
""",
    )
    a.add_argument(
        "-c",
        "--comment",
        metavar="TEXT",
        default="",
        help="announce upcoming maintenance with this message",
    )
    a.add_argument(
        "-d",
        "--spooldir",
        metavar="DIR",
        default=DEFAULT_DIR,
        help="request spool dir (default: %(default)s)",
    )
    a.add_argument(
        "estimate",
        metavar="ESTIMATE",
        help="estimate activity duration (suffixes: s, m, h)",
    )
    a.add_argument("-v", "--verbose", action="store_true", default=False)
    g = a.add_mutually_exclusive_group()
    g.add_argument(
        "-e",
        "--exec",
        metavar="SHELLCMD",
        default=False,
        help="execute shell command as maintenance activity",
    )
    g.add_argument(
        "file",
        metavar="FILE",
        default=None,
        nargs="?",
        type=argparse.FileType("r"),
        help="execute FILE as maintenance activity",
    )
    args = a.parse_args()
    init_logging(args.verbose)
    if args.file:
        act = args.file
    elif args.exec:
        act = io.StringIO(args.exec + "\n")
    else:
        act = sys.stdin

    with ReqManager(spooldir=args.spooldir) as rm:
        rm.scan()
        rm.add(
            Request(
                ShellScriptActivity(act), args.estimate, comment=args.comment
            )
        )
