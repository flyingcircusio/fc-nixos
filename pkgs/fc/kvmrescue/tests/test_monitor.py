"""Watching the evacuated VMs come back."""

import subprocess
import threading
import time
from collections import Counter

import pytest

import fc_kvmrescue as rescue

DEAD = "kvm05"
ROOT = "rbd.hdd/test00.root"


def watching(names):
    """A monitor over VMs that all have a root volume, as the step ensures."""
    roots = {name: f"rbd.hdd/{name}.root" for name in names}
    return rescue.VmMonitor(list(names), roots, DEAD)


def back(name, locker="kvm02"):
    """A VM that has come back: a new host holds the lock and it answers."""
    return rescue.VmStatus(name, locker, new_locker=True, pings=True)


@pytest.fixture
def poll(monkeypatch, lock):
    """Run one check_vm against a made-up lock holder and ping result."""

    def check(holder, pings, root_image=ROOT):
        monkeypatch.setattr(
            rescue, "list_locks", lambda image: [lock(holder)] if holder else []
        )
        monkeypatch.setattr(
            subprocess,
            "run",
            lambda *a, **k: subprocess.CompletedProcess(a, 0 if pings else 1),
        )
        return rescue.check_vm("test00", root_image, DEAD)

    return check


@pytest.mark.parametrize(
    ("holder", "pings", "healthy", "why"),
    [
        ("kvm02", True, True, "moved to another host and answering"),
        ("kvm02", False, False, "moved but still booting"),
        (DEAD, True, False, "the dead host took the lock back"),
        ("", True, False, "answering, but nobody holds the lock"),
        ("", False, False, "gone"),
    ],
)
def test_health_needs_a_new_locker_and_a_ping(
    poll, holder, pings, healthy, why
):
    assert poll(holder, pings).healthy is healthy, why


def test_the_lock_holder_is_reported(poll):
    assert poll("kvm02", True).locker == "kvm02"


def test_a_ceph_hiccup_does_not_end_the_watch(monkeypatch):
    """One bad round must not tear down a watch over 200 VMs."""

    def unwell(image):
        raise RuntimeError("image gone")

    monkeypatch.setattr(rescue, "list_locks", unwell)
    monkeypatch.setattr(
        subprocess, "run", lambda *a, **k: subprocess.CompletedProcess(a, 0)
    )

    status = rescue.check_vm("test00", ROOT, DEAD)

    assert status.locker == ""
    assert status.healthy is False


class TestVmMonitor:
    """The work queue: workers stay busy, states refresh when they go stale."""

    def drain(self, monitor, seconds=2.0):
        """Tick until everything is healthy, or give up."""
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if monitor.all_healthy:
                return True
            monitor.tick()
            time.sleep(0.001)
        return False

    def test_nothing_is_healthy_before_the_first_check(self):
        with watching(["vm00", "vm01"]) as monitor:
            assert monitor.all_healthy is False
            assert monitor.healthy_count == 0

    def test_finishes_once_every_vm_reports_back(self, monkeypatch):
        monkeypatch.setattr(
            rescue,
            "check_vm",
            lambda name, root, dead: back(name),
        )
        names = [f"vm{i:02}" for i in range(20)]

        with watching(names) as monitor:
            assert self.drain(monitor), "the watch never settled"
            assert monitor.healthy_count == 20

    def test_keeps_the_pool_busy_without_overfilling_it(self, monkeypatch):
        monkeypatch.setattr(rescue, "CHECK_WORKERS", 4)
        counter = threading.Lock()
        live = {"now": 0, "peak": 0}

        def slow(name, root, dead):
            with counter:
                live["now"] += 1
                live["peak"] = max(live["peak"], live["now"])
            time.sleep(0.01)
            with counter:
                live["now"] -= 1
            return back(name)

        monkeypatch.setattr(rescue, "check_vm", slow)

        with watching([f"vm{i:02}" for i in range(20)]) as m:
            self.drain(m)

        assert live["peak"] <= 4, "more checks in flight than workers"
        assert live["peak"] >= 2, "the pool was never actually saturated"

    def test_a_slow_vm_does_not_hold_up_the_others(self, monkeypatch):
        """The whole point: results land as they arrive, not in lockstep."""

        def check(name, root, dead):
            if name == "slowpoke":
                time.sleep(5)
            return back(name)

        monkeypatch.setattr(rescue, "check_vm", check)
        # Leave settled VMs alone, so only slowpoke is still in flight.
        monkeypatch.setattr(rescue, "POLL_INTERVAL", 3600)
        names = ["slowpoke", *[f"vm{i:02}" for i in range(5)]]

        with watching(names) as monitor:
            deadline = time.monotonic() + 0.5
            while time.monotonic() < deadline:
                monitor.tick()
                time.sleep(0.005)

            assert monitor.healthy_count == 5, "fast VMs should be in already"
            assert monitor.statuses["slowpoke"].healthy is False
            assert monitor.checking == ["slowpoke"]

    def test_a_vm_being_checked_is_visible(self, monkeypatch):
        started = threading.Event()

        def check(name, root, dead):
            started.set()
            time.sleep(5)
            return back(name)

        monkeypatch.setattr(rescue, "check_vm", check)

        with watching(["vm00"]) as monitor:
            monitor.tick()
            assert started.wait(timeout=2)
            assert monitor.statuses["vm00"].checking is True
            assert monitor.checking == ["vm00"]

    def test_rechecks_a_vm_once_its_state_is_outdated(self, monkeypatch):
        seen = Counter()

        def check(name, root, dead):
            seen[name] += 1
            return back(name)

        monkeypatch.setattr(rescue, "check_vm", check)
        monkeypatch.setattr(rescue, "POLL_INTERVAL", 0)

        with watching(["vm00"]) as monitor:
            deadline = time.monotonic() + 0.2
            while time.monotonic() < deadline:
                monitor.tick()
                time.sleep(0.005)

        assert seen["vm00"] > 1, "a stale state was never refreshed"

    def test_leaves_fresh_states_alone(self, monkeypatch):
        seen = Counter()

        def check(name, root, dead):
            seen[name] += 1
            return back(name)

        monkeypatch.setattr(rescue, "check_vm", check)
        monkeypatch.setattr(rescue, "POLL_INTERVAL", 3600)

        with watching(["vm00"]) as monitor:
            self.drain(monitor, seconds=0.2)

        assert seen["vm00"] == 1

    def test_oldest_information_is_refreshed_first(self, monkeypatch):
        monkeypatch.setattr(rescue, "CHECK_WORKERS", 1)
        order = []

        def check(name, root, dead):
            order.append(name)
            return back(name)

        monkeypatch.setattr(rescue, "check_vm", check)

        with watching(["a", "b", "c"]) as monitor:
            monitor.statuses["a"].checked_at = time.monotonic()
            monitor.statuses["b"].checked_at = time.monotonic() - 100
            monitor.statuses["c"].checked_at = time.monotonic() - 500
            monkeypatch.setattr(rescue, "POLL_INTERVAL", 10)
            for _ in range(3):
                monitor.tick()
                time.sleep(0.05)

        assert order[:2] == ["c", "b"], order

    def test_a_failing_check_is_reported_and_retried(self, monkeypatch, output):
        """One unhappy VM must not end a watch over 200 of them."""
        attempts = Counter()

        def boom(name, root, dead):
            attempts[name] += 1
            raise OSError("ping: command not found")

        monkeypatch.setattr(rescue, "check_vm", boom)

        with watching(["vm00"]) as monitor:
            deadline = time.monotonic() + 0.3
            while time.monotonic() < deadline:
                monitor.tick()
                time.sleep(0.005)

            assert monitor.all_healthy is False

        assert attempts["vm00"] > 1, "a failed check was never retried"
        assert "Checking vm00 failed" in output.getvalue()


class TestMonitorStep:
    def test_stops_once_every_vm_is_back(self, monkeypatch, make_state, output):
        names = [f"vm{i:02}" for i in range(12)]
        state = make_state(DEAD)
        state.locked_images = {f"rbd.hdd/{name}.root": [] for name in names}
        monkeypatch.setattr(
            rescue,
            "check_vm",
            lambda name, root, dead: back(name),
        )

        rescue.Rescue(state).monitor_affected_vms()

        assert "All 12 VMs are back." in output.getvalue()

    def test_skips_and_warns_about_a_vm_without_a_root_volume(
        self, monkeypatch, make_state, output
    ):
        """Such a VM cannot exist, and would never answer a ping either."""
        state = make_state(DEAD)
        state.locked_images = {
            "rbd.hdd/good.root": [],
            "rbd.ssd/good.swap": [],
            "rbd.ssd/rootless.swap": [],
        }
        watched = []

        def check(name, root, dead):
            watched.append(name)
            return back(name)

        monkeypatch.setattr(rescue, "check_vm", check)

        rescue.Rescue(state).monitor_affected_vms()

        assert set(watched) == {"good"}
        assert any("rootless has no root volume" in w for w in state.warnings)
        assert "All 1 VMs are back." in output.getvalue()

    def test_stops_when_no_vm_has_a_root_volume(
        self, monkeypatch, make_state, output
    ):
        state = make_state(DEAD)
        state.locked_images = {"rbd.ssd/a.swap": [], "rbd.ssd/b.tmp": []}
        monkeypatch.setattr(
            rescue,
            "check_vm",
            lambda *a: pytest.fail("a rootless VM was monitored"),
        )

        rescue.Rescue(state).monitor_affected_vms()

        assert "No VM has a root volume to watch." in output.getvalue()
        assert len(state.warnings) == 2

    def test_says_so_when_nothing_was_affected(self, make_state, output):
        rescue.Rescue(make_state(DEAD)).monitor_affected_vms()
        assert "no monitoring necessary" in output.getvalue()
