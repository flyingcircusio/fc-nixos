"""Step registration and the sequence run_rescue walks."""

import pytest

import fc_kvmrescue as rescue


def step_names():
    return list(rescue.Rescue.all_steps())


def stub_step(original, body):
    """A stand-in Step that keeps the metadata of the one it replaces."""
    body.__name__ = original.name
    body.__doc__ = original.description
    return rescue.Step(body, always=original.always, number=original.number)


@pytest.fixture
def steps(monkeypatch):
    """Replace every step with a recorder, leaving only the runner under test."""
    called = []
    for original in rescue.Rescue.all_steps().values():

        def stub(self, _name=original.name):
            called.append(_name)

        monkeypatch.setattr(
            rescue.Rescue, original.name, stub_step(original, stub)
        )
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
        """The sequence is read off the class, not a registry."""
        names = step_names()
        assert names[0] == "register_ticket"
        assert names[-1] == "set_back_in_service"
        assert names.index("break_locks") > names.index("collect_locks")

    def test_each_step_carries_its_own_metadata(self):
        step = rescue.Rescue.all_steps()["ensure_host_offline"]
        assert step.name == "ensure_host_offline"
        assert step.description == "Fence off host"
        assert step.always is True
        assert repr(step) == "<Step ensure_host_offline>"

    def test_steps_are_numbered_by_their_place_in_the_sequence(self):
        steps = list(rescue.Rescue.all_steps().values())
        assert [step.number for step in steps] == list(range(1, len(steps) + 1))
        assert steps[0].number == 1

    def test_binding_keeps_the_number_and_adds_the_rescue(self, make_state):
        instance = rescue.Rescue(make_state())
        declared = rescue.Rescue.all_steps()["collect_locks"]
        bound = instance.steps["collect_locks"]

        assert bound.number == declared.number
        assert bound.rescue is instance
        assert declared.rescue is None

    def test_only_the_safety_gates_always_run(self):
        always = {
            step.name
            for step in rescue.Rescue.all_steps().values()
            if step.always
        }
        assert always == {
            "ensure_host_offline",
            "monitor_affected_vms",
            "cleanup_check_machine_is_clean",
        }

    def test_reaching_for_a_step_by_name_gives_a_bound_call(self, make_state):
        """What `__get__` is for: without it the body runs with no rescue."""
        instance = rescue.Rescue(make_state())
        seen = []

        def body(self):
            seen.append(self)

        body.__name__ = "collect_locks"
        declared = rescue.Step(body)

        assert declared.__get__(None) is declared  # on the class: the step
        declared.__get__(instance)()  # on an instance: a bound call
        assert seen == [instance]

    def test_a_bound_step_calls_its_own_method(self, make_state):
        """The runner path does not go back through attribute lookup."""
        instance = rescue.Rescue(make_state())
        seen = []

        def body(self):
            seen.append(self)

        body.__name__ = "collect_locks"
        rescue.Step(body).bind(instance)()

        assert seen == [instance]
        assert "collect_locks" in instance.state.completed

    def test_every_step_is_documented(self):
        assert all(
            step.description for step in rescue.Rescue.all_steps().values()
        )


class TestSequence:
    def test_a_full_run_walks_every_step(self, steps):
        run("kvm01")
        assert steps == step_names()

    def test_a_second_run_only_repeats_the_always_run_steps(self, steps):
        run("kvm01")
        steps.clear()

        run("kvm01")

        assert steps == [
            "ensure_host_offline",
            "monitor_affected_vms",
            "cleanup_check_machine_is_clean",
        ]

    def test_run_all_repeats_everything(self, steps):
        run("kvm01")
        steps.clear()

        run("kvm01", "--run-all")

        assert steps == step_names()

    def test_a_failed_step_stays_unrecorded(self, steps, monkeypatch):
        def explode(self):
            raise RuntimeError("ceph is unwell")

        monkeypatch.setattr(
            rescue.Rescue,
            "collect_locks",
            stub_step(rescue.Rescue.all_steps()["collect_locks"], explode),
        )

        with pytest.raises(RuntimeError):
            run("kvm01")

        done = rescue.RescueState.load("kvm01").completed
        assert "collect_locks" not in done
        assert "set_out_of_service" in done


class TestSingleStep:
    def test_runs_only_the_named_step(self, steps):
        run("kvm01", "--step", "break_locks")
        assert steps == ["break_locks"]

    def test_records_the_step_it_ran(self, steps):
        run("kvm01", "--step", "break_locks")
        assert rescue.RescueState.load("kvm01").completed == ["break_locks"]


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
