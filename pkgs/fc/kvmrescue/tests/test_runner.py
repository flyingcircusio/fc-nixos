"""Step registration and the sequence run_rescue walks."""

import pytest

import fc_kvmrescue as rescue


@pytest.fixture
def steps(monkeypatch):
    """Replace every step with a recorder, leaving only the runner under test."""
    called = []
    for name in rescue.STEPS:

        def stub(self, _name=name):
            called.append(_name)

        monkeypatch.setattr(rescue.Rescue, name, stub)
    monkeypatch.setattr(
        rescue,
        "open_state",
        lambda host: rescue.RescueState.load(host) or rescue.new_state(host),
    )
    return called


def run(*argv):
    return rescue.run_rescue(["fc-kvmrescue", *argv])


class TestRegistration:
    def test_definition_order_is_run_order(self):
        assert rescue.STEPS[0] == "register_ticket"
        assert rescue.STEPS[-1] == "set_back_in_service"
        assert rescue.STEPS.index("break_locks") > rescue.STEPS.index(
            "collect_locks"
        )

    def test_always_run_comes_from_the_decorator(self):
        assert rescue.ALWAYS_RUN == {
            "ensure_host_offline",
            "monitor_affected_vms",
            "cleanup_check_machine_is_clean",
        }
        assert rescue.ALWAYS_RUN <= set(rescue.STEPS)

    def test_both_decorator_spellings_keep_the_method(self):
        """`@step` and `@step(always=True)` must both hand the method back."""
        assert rescue.step_doc("register_ticket") == "Register rescue ticket"
        assert rescue.step_doc("ensure_host_offline") == "Fence off host"
        assert rescue.Rescue.ensure_host_offline.__name__ == (
            "ensure_host_offline"
        )

    def test_every_step_is_documented(self):
        assert all(rescue.step_doc(name) for name in rescue.STEPS)


class TestSequence:
    def test_a_full_run_walks_every_step(self, steps):
        run("kvm01")
        assert steps == rescue.STEPS

    def test_a_second_run_only_repeats_the_always_run_steps(self, steps):
        run("kvm01")
        steps.clear()

        run("kvm01")

        assert steps == [
            "ensure_host_offline",
            "monitor_affected_vms",
            "cleanup_check_machine_is_clean",
        ]

    def test_no_skip_repeats_everything(self, steps):
        run("kvm01")
        steps.clear()

        run("kvm01", "--no-skip")

        assert steps == rescue.STEPS

    def test_a_failed_step_stays_unrecorded(self, steps, monkeypatch):
        def explode(self):
            raise RuntimeError("ceph is unwell")

        monkeypatch.setattr(rescue.Rescue, "collect_locks", explode)

        with pytest.raises(RuntimeError):
            run("kvm01")

        done = rescue.RescueState.load("kvm01").completed
        assert "collect_locks" not in done
        assert "set_out_of_service" in done


class TestSingleStep:
    def test_refuses_when_earlier_steps_have_not_run(self, steps, output):
        assert run("kvm01", "--step", "break_locks") == 1
        assert steps == []
        assert "requires steps that have not run yet" in output.getvalue()

    def test_runs_alone_once_the_prerequisites_are_met(self, steps):
        run("kvm01")
        steps.clear()

        run("kvm01", "--step", "break_locks")

        assert steps == ["break_locks"]

    def test_names_the_next_step(self, steps, output):
        run("kvm01")
        run("kvm01", "--step", "break_locks")
        assert "Next step to invoke manually would be evacuate_vms" in (
            output.getvalue()
        )


class TestCommandLine:
    def test_the_positional_argument_is_the_host(self):
        args = rescue.parse_args(["kvm05"])
        assert args.kvmhostname == "kvm05"
        assert not hasattr(args, "yt_ticket")

    def test_list_needs_no_state(self, output):
        assert run("--list") == 0
        assert "Register rescue ticket" in output.getvalue()

    def test_list_reports_a_missing_state_file(self, output):
        assert run("--list", "kvm99") == 0
        assert "Unable to load state file" in output.getvalue()

    def test_list_marks_completed_steps(self, steps, output):
        run("kvm01")
        output.truncate(0)
        output.seek(0)

        run("--list", "kvm01")

        assert "done" in output.getvalue()
