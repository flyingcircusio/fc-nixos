import traceback
import unittest.mock
from typing import NamedTuple
from unittest.mock import Mock

import fc.manage.collect_garbage
import typer.testing


class PwUserEntry(NamedTuple):
    pw_dir: str
    pw_uid: int
    pw_gid: int
    pw_name: str

class GroupEntry(NamedTuple):
    gr_name: str
    gr_gid: int


@unittest.mock.patch("subprocess.Popen")
@unittest.mock.patch("subprocess.run")
@unittest.mock.patch("pwd.getpwall")
@unittest.mock.patch("grp.getgrnam")
@unittest.mock.patch("fc.util.lock.locked")
def test_invoke(locked, getgrnam, getpwall: Mock, run, popen, tmp_path, log, logger):
    getgrnam.return_value = GroupEntry("users", 100)
    getpwall.return_value = [
        PwUserEntry("/srv/system", 400, 400, "system"),
        PwUserEntry("/var/empty", 1002, 993, "emptyhomedir"),
        PwUserEntry("/home/human", 1001, 100, "human"),
        PwUserEntry("/srv/s-service", 1003, 900, "s-service"),
    ]
    popen.return_value.wait.return_value = 0
    run.return_value.returncode = 0
    runner = typer.testing.CliRunner()
    exclude_file = tmp_path / "fc-userscan.exclude"
    exclude_file.write_text("ignorethis", encoding="utf8")
    ignore_user_file = tmp_path / "fc-userscan.ignore_users"
    ignore_user_file.write_text("notthisuser", encoding="utf8")
    gcroot = tmp_path / "gcroot"
    delete_gcroots = {
        gcroot / "human" / "home" / "human": True,
        gcroot / "human" / "manual": False,
        gcroot / "unknown": True,
        gcroot / "s-service" / "home": False,
        gcroot / "system" / "home": False,
    }
    for p in delete_gcroots:
        p.mkdir(parents=True)
        (p / "test").symlink_to(ignore_user_file)

    args = (
        "--verbose",
        "--stamp-dir",
        str(tmp_path),
        "--lock-dir",
        str(tmp_path),
        "--exclude-file",
        exclude_file,
        "--ignore-users-file",
        ignore_user_file,
    )
    with unittest.mock.patch("fc.manage.collect_garbage.GCROOTS", gcroot):
        result = runner.invoke(fc.manage.collect_garbage.app, args)

    if result.exc_info:
        traceback.print_tb(result.exc_info[2])
    assert result.exit_code == 0, (
        f"unexpected exit code, output: {result.output}"
    )

    assert log.has("collect-garbage-start")
    assert log.has("collect-garbage-succeeded")
    for p, delete in delete_gcroots.items():
        if delete:
            assert log.has("gcroots-deleted", path=str(p))
            assert not p.exists()
        else:
            assert p.exists()
    assert ignore_user_file.exists()
    #  Should ignore users system, emptyhome, human, unknown and just scan /srv/s-service
    assert log.has("userscan-start", user_count=1)
