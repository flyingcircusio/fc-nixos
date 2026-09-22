"""`--dry-run` must not change the cluster, the host, or anything else."""

import pytest

import fc_kvmrescue as rescue

CHANGES = (
    "blocklist add",
    "blocklist rm",
    "lock remove",
    "power on",
    "power off",
)


def destructive(argv):
    joined = " ".join(argv)
    return "fc-directory" in argv[0] or any(c in joined for c in CHANGES)


@pytest.fixture
def evacuated(make_state, lock):
    """A rescue that has already collected locks and blocklisted them."""
    state = make_state("kvm05", ipmi_user="ADMIN")
    state.locked_images = {"rbd.hdd/alpha.root": [lock("kvm05")]}
    state.blocklist = ["172.20.4.101:0/0"]
    rescued = rescue.Rescue(state)
    rescued.ipmi.password = "secret"
    return rescued


def exercise(rescued):
    rescued.blocklist_lockers()
    rescued.break_locks()
    rescued.evacuate_vms()
    rescued.blocklist_cleanup()
    rescued.ipmi.change("power", "on")


def test_nothing_destructive_escapes(monkeypatch, evacuated, fake_run):
    monkeypatch.setattr(rescue, "DRY_RUN", True)
    calls = fake_run()

    exercise(evacuated)

    assert [c for c in calls if destructive(c)] == []


def test_every_skipped_command_is_shown(
    monkeypatch, evacuated, fake_run, output
):
    monkeypatch.setattr(rescue, "DRY_RUN", True)
    fake_run()

    exercise(evacuated)

    shown = [
        line
        for line in output.getvalue().splitlines()
        if line.strip().startswith("$ ")
    ]
    assert len(shown) == 5


def test_a_live_run_does_execute_them(evacuated, fake_run):
    calls = fake_run()

    exercise(evacuated)

    assert len([c for c in calls if destructive(c)]) == 5


def test_the_monitor_does_not_wait_for_an_evacuation_that_never_happened(
    monkeypatch, evacuated
):
    """Nothing moved, so polling would never finish."""
    monkeypatch.setattr(rescue, "DRY_RUN", True)

    def forbidden(*args, **kwargs):
        raise AssertionError("dry run polled the VMs")

    monkeypatch.setattr(rescue, "check_vm", forbidden)
    evacuated.monitor_affected_vms()


def test_read_only_commands_still_run(monkeypatch, fake_run):
    """A rehearsal is worthless if it cannot look at the cluster."""
    monkeypatch.setattr(rescue, "DRY_RUN", True)
    calls = fake_run({"pool application get": "{}"})

    rescue.rbd_pools()

    assert any("pool application get" in " ".join(call) for call in calls)
