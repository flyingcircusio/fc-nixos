"""Watching the evacuated VMs come back."""

import subprocess

import pytest

import fc_kvmrescue as rescue

DEAD = "kvm05"
ROOT = "rbd.hdd/test00.root"


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


def test_without_a_known_root_image_the_ping_decides(poll):
    assert poll("", True, root_image="").healthy is True
    assert poll("", False, root_image="").healthy is False


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


class TestLoop:
    @pytest.fixture
    def fleet(self, make_state):
        names = [f"vm{i:02}" for i in range(12)]
        state = make_state(DEAD)
        state.locked_images = {f"rbd.hdd/{name}.root": [] for name in names}
        return state, names

    def test_stops_once_every_vm_is_back(self, monkeypatch, fleet, output):
        state, names = fleet
        rounds = {"n": 0}

        def check(name, root, dead):
            back = rounds["n"] * 4 > names.index(name)
            return rescue.VmStatus(name, "kvm02" if back else "", back, back)

        def tick(_):
            rounds["n"] += 1
            assert rounds["n"] < 20, "the watch never finished"

        monkeypatch.setattr(rescue, "check_vm", check)
        monkeypatch.setattr(rescue, "sleep", tick)

        rescue.Rescue(state).monitor_affected_vms()

        assert "All 12 VMs are back." in output.getvalue()

    def test_polls_every_vm_each_round(self, monkeypatch, fleet):
        state, names = fleet
        rounds = {"n": 0}
        polled = []

        def check(name, root, dead):
            polled.append((rounds["n"], name))
            return rescue.VmStatus(name, "kvm02", True, rounds["n"] > 0)

        monkeypatch.setattr(rescue, "check_vm", check)
        monkeypatch.setattr(
            rescue, "sleep", lambda _: rounds.__setitem__("n", rounds["n"] + 1)
        )

        rescue.Rescue(state).monitor_affected_vms()

        per_round = {}
        for round_number, name in polled:
            per_round.setdefault(round_number, set()).add(name)
        assert per_round[0] == set(names)
        assert per_round[1] == set(names)

    def test_says_so_when_nothing_was_affected(self, make_state, output):
        rescue.Rescue(make_state(DEAD)).monitor_affected_vms()
        assert "no monitoring necessary" in output.getvalue()
