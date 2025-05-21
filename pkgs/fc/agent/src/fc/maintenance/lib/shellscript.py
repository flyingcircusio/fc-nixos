"""Create scheduled maintenance with a shell script activity.

The maintenance activity script can be given either on the command line
or as a separate file. In case that there is no shebang line in the
file, it is executed with /bin/sh.
"""

import os
import subprocess

import rich.console
import rich.syntax
import rich.text

from ..activity import Activity


class ShellScriptActivity(Activity):
    def __init__(self, script):
        super().__init__()
        self.script = script

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

    def __rich__(self):
        lines = self.script.splitlines()
        syntax = rich.syntax.Syntax(
            self.script, "shell", line_numbers=len(lines) > 2
        )
        return rich.console.Group("Execute script:\n", syntax)
