"""Shared fixtures.

Everything that could reach outside the test process -- the state directory,
the console, and above all `subprocess` -- is replaced by default, so a test
that forgets to stub something fails loudly instead of running `rbd`, `ping`
or `fc-ipmitool` against a real cluster.
"""

import io
import subprocess
from datetime import UTC, datetime

import pytest
from rich.console import Console

import fc_kvmrescue as rescue


@pytest.fixture(autouse=True)
def state_dir(tmp_path, monkeypatch):
    """Keep tests away from the real /var/lib/fc-kvmrescue."""
    directory = tmp_path / "state"
    monkeypatch.setattr(rescue, "STATE_DIR", directory)
    return directory


@pytest.fixture(autouse=True)
def output(monkeypatch):
    """Capture what the script prints, at a fixed terminal size."""
    buffer = io.StringIO()
    monkeypatch.setattr(
        rescue,
        "console",
        Console(
            file=buffer,
            force_terminal=False,
            width=100,
            height=20,
            highlight=False,
        ),
    )
    return buffer


@pytest.fixture(autouse=True)
def defaults(monkeypatch):
    """A live run that never waits between polls."""
    monkeypatch.setattr(rescue, "DRY_RUN", False)
    monkeypatch.setattr(rescue, "POLL_INTERVAL", 0)
    monkeypatch.setattr(rescue, "sleep", lambda seconds: None)


@pytest.fixture(autouse=True)
def no_subprocess(monkeypatch):
    """Shelling out is opt-in: a test that means to must say so."""

    def forbidden(cmd, *args, **kwargs):
        raise AssertionError(f"unexpected subprocess call: {cmd}")

    monkeypatch.setattr(subprocess, "run", forbidden)


@pytest.fixture
def make_state():
    """Build a RescueState without touching the disk."""

    def build(hostname="kvm05", **fields):
        return rescue.RescueState(
            kvmhostname=hostname, created=datetime.now(tz=UTC), **fields
        )

    return build


@pytest.fixture
def lock():
    """An `rbd lock ls` entry held by `host`."""

    def build(host, address="172.20.4.101:0/111"):
        return rescue.RbdLock(id=host, locker="client.1", address=address)

    return build


@pytest.fixture
def fake_run(monkeypatch):
    """Record every argv and answer it from a {substring: stdout} table."""

    def install(replies=None):
        calls = []

        def run(cmd, *args, **kwargs):
            calls.append(list(cmd))
            joined = " ".join(cmd)
            for needle, stdout in (replies or {}).items():
                if needle in joined:
                    return subprocess.CompletedProcess(cmd, 0, stdout, "")
            return subprocess.CompletedProcess(cmd, 0, "", "")

        monkeypatch.setattr(subprocess, "run", run)
        return calls

    return install
