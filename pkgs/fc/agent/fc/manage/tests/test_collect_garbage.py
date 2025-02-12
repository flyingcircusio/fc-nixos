import traceback
import unittest.mock
from typing import NamedTuple
from unittest.mock import MagicMock, Mock

import fc.manage.collect_garbage
import typer.testing
from fc.util.tests import PollingFakePopen


class PwUserEntry(NamedTuple):
    pw_dir: str
    pw_uid: int
    pw_name: str


def test_invoke(tmp_path, logger, monkeypatch):
    run_userscan = Mock()
    monkeypatch.setattr(
        fc.manage.collect_garbage, "run_userscan", run_userscan
    )
    run_nix_collect_garbage = Mock()
    monkeypatch.setattr(
        fc.manage.collect_garbage,
        "run_nix_collect_garbage",
        run_nix_collect_garbage,
    )

    exclude_file = tmp_path / "fc-userscan.exclude"
    exclude_file.touch()
    ignore_user_file = tmp_path / "fc-userscan.ignore_users"
    ignore_user_file.touch()

    stamp_file = tmp_path / "fc-collect-garbage_last_run.stamp"

    args = (
        "--verbose",
        "--logdir",
        tmp_path,
        "--lock-dir",
        tmp_path,
        "--exclude-file",
        exclude_file,
        "--ignore-users-file",
        ignore_user_file,
        "--stamp-file",
        stamp_file,
    )

    monkeypatch.setattr("os.getuid", lambda: 0)

    runner = typer.testing.CliRunner()
    result = runner.invoke(fc.manage.collect_garbage.app, args)

    if result.exc_info:
        traceback.print_tb(result.exc_info[2])
    assert result.exit_code == 0, (
        f"unexpected exit code, output: " f" {result.output}"
    )

    run_userscan.assert_called_once()
    run_nix_collect_garbage.assert_called_once()

    assert stamp_file.exists()


def test_run_userscan(tmp_path, log, logger, monkeypatch):
    getpwall = Mock(
        return_value=[
            PwUserEntry("/srv/system", 400, "system"),
            PwUserEntry("/var/empty", 1002, "emptyhomedir"),
            PwUserEntry(str(tmp_path), 1001, "scanthis"),
            PwUserEntry("/home/notthisuser", 1002, "notthisuser"),
        ]
    )
    monkeypatch.setattr("pwd.getpwall", getpwall)

    userscan_fake = PollingFakePopen(
        "fc-userscan",
        stderr="test",
        returncode=0,
    )
    popen = Mock(return_value=userscan_fake)
    monkeypatch.setattr("subprocess.Popen", popen)

    exclude_file = tmp_path / "fc-userscan.exclude"
    exclude_file.write_text("ignorethis")
    ignore_user_file = tmp_path / "fc-userscan.ignore_users"
    ignore_user_file.write_text("notthisuser")
    exclude_file = tmp_path / "fc-userscan.exclude"
    exclude_file.write_text("ignorethis")

    user_specific_ignore_file = tmp_path / ".userscan-ignore"
    user_specific_ignore_file.write_text("dontscan")

    fc.manage.collect_garbage.run_userscan(
        logger, exclude_file, ignore_user_file, verbose=True
    )

    #  Should ignore users system, emptyhome, notthisusers and just scan /home/normal
    assert log.has("userscan-start", user_count=1)
    assert log.has("userscan-user", name="scanthis")
    assert log.has("userscan-cache-not-found")
    assert log.has("userscan-ignore-found")
    assert log.has("userscan-out", cmd_output_line="test")


def test_run_nix_collect_garbage(tmp_path, log, logger, monkeypatch):

    garbage_collect_fake = PollingFakePopen(
        "nix-collect-garbage",
        stderr="test",
        returncode=0,
    )

    popen = Mock(return_value=garbage_collect_fake)
    monkeypatch.setattr("subprocess.Popen", popen)

    locked = MagicMock()
    monkeypatch.setattr("fc.util.lock.locked", locked)

    fc.manage.collect_garbage.run_nix_collect_garbage(
        logger, lock_dir=tmp_path
    )

    locked.return_value.__enter__.assert_called_once()

    assert log.has("collect-garbage-start")
    assert log.has("collect-garbage-succeeded")
