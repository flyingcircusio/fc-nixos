"""Talking to Ceph: pool discovery and collecting the dead host's locks."""

import json
import subprocess

import pytest

import fc_kvmrescue as rescue

POOLS = {
    "rbd.hdd": {"rbd": {}},
    "rbd.ssd": {"rbd": {}},
    "cephfs_data": {"cephfs": {}},
    ".mgr": {"mgr": {}},
    "stale": {},
}


def test_rbd_pools_only_takes_the_rbd_application(monkeypatch):
    monkeypatch.setattr(rescue, "ceph", lambda *a, **k: json.dumps(POOLS))
    assert rescue.rbd_pools() == ["rbd.hdd", "rbd.ssd"]


def test_rbd_pools_copes_with_an_empty_cluster(monkeypatch):
    monkeypatch.setattr(rescue, "ceph", lambda *a, **k: "{}")
    assert rescue.rbd_pools() == []


def test_list_images_prefixes_the_pool(fake_run):
    fake_run({"rbd": json.dumps(["vm-alpha", "vm-beta"])})
    assert rescue.list_images("rbd.hdd") == [
        "rbd.hdd/vm-alpha",
        "rbd.hdd/vm-beta",
    ]


def test_rbd_explains_a_vanished_image(monkeypatch):
    def gone(cmd, *args, **kwargs):
        raise subprocess.CalledProcessError(
            2,
            cmd,
            stderr="error opening image foo: (2) No such file or directory",
        )

    monkeypatch.setattr(subprocess, "run", gone)
    with pytest.raises(RuntimeError, match="collect_locks"):
        rescue.rbd("lock", "ls", "rbd.hdd/foo")


def test_rbd_passes_other_failures_through(monkeypatch):
    def broken(cmd, *args, **kwargs):
        raise subprocess.CalledProcessError(1, cmd, stderr="connection timeout")

    monkeypatch.setattr(subprocess, "run", broken)
    with pytest.raises(subprocess.CalledProcessError):
        rescue.rbd("lock", "ls", "rbd.hdd/foo")


class TestCollectLocks:
    @pytest.fixture
    def cluster(self, monkeypatch, lock):
        monkeypatch.setattr(rescue, "ceph", lambda *a, **k: json.dumps(POOLS))
        images = {
            "rbd.hdd": ["alpha.root", "beta.root"],
            "rbd.ssd": ["gamma.root"],
        }
        locks = {
            "rbd.hdd/alpha.root": [lock("kvm05", "172.20.4.101:0/111")],
            # beta belongs to a different host and must be left alone
            "rbd.hdd/beta.root": [lock("kvm02", "172.20.4.102:0/222")],
            "rbd.ssd/gamma.root": [
                lock("kvm05", "[fe80::1]:0/333"),
                lock("kvm09", "172.20.4.109:0/9"),
            ],
        }
        monkeypatch.setattr(
            rescue,
            "list_images",
            lambda pool: [f"{pool}/{name}" for name in images[pool]],
        )
        monkeypatch.setattr(
            rescue, "list_locks", lambda image: locks.get(image, [])
        )

    def test_keeps_only_images_the_dead_host_locked(self, cluster, make_state):
        state = make_state("kvm05")
        rescue.Rescue(state).collect_locks()
        assert sorted(state.locked_images) == [
            "rbd.hdd/alpha.root",
            "rbd.ssd/gamma.root",
        ]

    def test_warns_about_a_shared_lock(self, cluster, make_state):
        state = make_state("kvm05")
        rescue.Rescue(state).collect_locks()
        assert any(
            "locking is expected to be exclusive" in warning
            for warning in state.warnings
        )

    def test_keeps_the_foreign_lock_alongside_ours(self, cluster, make_state):
        """break_locks needs both to tell them apart."""
        state = make_state("kvm05")
        rescue.Rescue(state).collect_locks()
        holders = {
            lock.id for lock in state.locked_images["rbd.ssd/gamma.root"]
        }
        assert holders == {"kvm05", "kvm09"}

    def test_survives_a_host_that_locked_nothing(self, cluster, make_state):
        state = make_state("kvm42")
        rescue.Rescue(state).collect_locks()
        assert state.locked_images == {}
