import traceback
import unittest.mock
from typing import NamedTuple
from unittest.mock import Mock

import fc.manage.collect_garbage
import typer.testing


class PwUserEntry(NamedTuple):
    pw_dir: str
    pw_uid: int
    pw_name: str


@unittest.mock.patch("subprocess.Popen")
@unittest.mock.patch("subprocess.run")
@unittest.mock.patch("pwd.getpwall")
@unittest.mock.patch("fc.util.lock.locked")
def test_invoke(locked, getpwall: Mock, run, popen, tmpdir, log, logger):
    getpwall.return_value = [
        PwUserEntry("/srv/system", 400, "system"),
        PwUserEntry("/var/empty", 1002, "emptyhomedir"),
        PwUserEntry("/home/normal", 1001, "normal"),
    ]
    popen.return_value.wait.return_value = 0
    run.return_value.returncode = 0
    runner = typer.testing.CliRunner()
    exclude_file = tmpdir / "fc-userscan.exclude"
    exclude_file.write_text("ignorethis", encoding="utf8")

    args = (
        "--verbose",
        "--stamp-dir",
        tmpdir,
        "--lock-dir",
        tmpdir,
        "--exclude-file",
        exclude_file,
    )
    result = runner.invoke(fc.manage.collect_garbage.app, args)

    if result.exc_info:
        traceback.print_tb(result.exc_info[2])
    assert result.exit_code == 0, (
        f"unexpected exit code, output:" f" {result.output}"
    )

    assert log.has("collect-garbage-start")
    assert log.has("collect-garbage-succeeded")
    #  Should ignore users system, emptyhome and just scan /home/normal
    assert log.has("userscan-start", user_count=1)
