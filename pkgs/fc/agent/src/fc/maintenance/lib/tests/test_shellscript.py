import os

import fc.maintenance.state
import pytest
from fc.maintenance.lib.shellscript import ShellScriptActivity


def test_sh_script(tmpdir):
    os.chdir(str(tmpdir))
    script = 'echo "hello"; echo "world" >&2; exit 5\n'
    a = ShellScriptActivity(script)
    a.run()
    assert a.stdout == "hello\n"
    assert a.stderr == "world\n"
    assert a.returncode == 5


@pytest.mark.skipif(
    not os.path.exists("/usr/bin/env"),
    reason="not expected to run inside a chroot",
)
def test_python_script(tmpdir):
    os.chdir(str(tmpdir))
    script = """\
#!/usr/bin/env python3
import sys
print('hello')
print('world', file=sys.stderr)
sys.exit(5)
"""
    a = ShellScriptActivity(script)
    a.run()
    assert a.stdout == "hello\n"
    assert a.stderr == "world\n"
    assert a.returncode == 5


def test_shellscript_should_be_not_resumable():
    activity = ShellScriptActivity("true")
    activity.resume()
    assert activity.returncode == fc.maintenance.state.EXIT_INTERRUPTED
