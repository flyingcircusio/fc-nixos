"""The two interactive safety gates, driven by scripted operator answers.

`ensure_host_offline` and `cleanup_check_host_fence` are the steps that
decide whether it is safe to touch the locks and whether the host may come
back. They are also the branchiest code in the script, so every way out of
them is pinned down here.
"""

import subprocess

import pytest

import fc_kvmrescue as rescue


class FakeIpmi:
    """Stands in for the BMC: scripted power states, recorded commands."""

    def __init__(self, power_states, fail_on=()):
        self.power_states = list(power_states)
        self.fail_on = fail_on
        self.commands = []

    def is_powered_off(self):
        return self.power_states.pop(0)

    def change(self, *args):
        self.commands.append(("change",) + args)
        if args in self.fail_on:
            raise subprocess.CalledProcessError(1, ["fc-ipmitool", *args])

    def interactive(self, *args):
        self.commands.append(("interactive",) + args)


@pytest.fixture
def gate(make_state, monkeypatch):
    """A Rescue wired to a fake BMC and a scripted set of menu answers."""

    def build(power_states, answers=(), confirms=(), fail_on=()):
        state = make_state("kvm05", ipmi_user="ADMIN")
        rescued = rescue.Rescue(state)
        rescued._ipmi = FakeIpmi(power_states, fail_on)
        replies = list(answers)
        monkeypatch.setattr(
            rescue.Prompt, "ask", lambda *a, **k: replies.pop(0)
        )
        yeses = list(confirms)
        monkeypatch.setattr(
            rescue, "confirm", lambda *a, **k: yeses.pop(0) if yeses else True
        )
        return rescued

    return build


class TestEnsureHostOffline:
    def test_a_host_that_is_already_off_asks_nothing(self, gate):
        rescued = gate(power_states=[True])
        rescued.ensure_host_offline()
        assert rescued._ipmi.commands == []

    def test_skips_once_the_main_rescue_is_done(self, gate, output):
        """It runs on every pass, so it must not re-fence during cleanup."""
        rescued = gate(power_states=[])
        rescued.state.completed = ["cleanup_start"]

        rescued.ensure_host_offline()

        assert "already finished" in output.getvalue()

    @pytest.mark.parametrize("answer", ["1", "power off"])
    def test_powering_off_and_rechecking(self, gate, answer):
        rescued = gate(power_states=[False, True], answers=[answer])

        rescued.ensure_host_offline()

        assert rescued._ipmi.commands == [("change", "power", "off")]
        assert rescued._ipmi.power_states == []

    @pytest.mark.parametrize(
        ("answer", "expected"),
        [
            ("2", ("interactive", "sol", "activate")),
            ("SOL", ("interactive", "sol", "activate")),
            ("3", ("interactive", "shell")),
            ("shell", ("interactive", "shell")),
        ],
    )
    def test_investigating_then_finding_it_off(self, gate, answer, expected):
        rescued = gate(power_states=[False, True], answers=[answer])

        rescued.ensure_host_offline()

        assert rescued._ipmi.commands == [expected]

    @pytest.mark.parametrize("answer", ["0", "continue"])
    def test_continuing_anyway_leaves_the_host_running(self, gate, answer):
        """The operator may override; nothing forces the host off."""
        rescued = gate(power_states=[False], answers=[answer])

        rescued.ensure_host_offline()

        assert rescued._ipmi.commands == []

    def test_a_flaky_bmc_does_not_abort_the_step(self, gate, output):
        rescued = gate(
            power_states=[False, False, True],
            answers=["1", "1"],
            fail_on=[("power", "off")],
        )

        rescued.ensure_host_offline()

        assert len(rescued._ipmi.commands) == 2
        assert "Command" in output.getvalue()  # the CalledProcessError text


class TestCleanupCheckMachineIsClean:
    def test_a_powered_off_host_is_clean(self, gate, output):
        rescued = gate(power_states=[True])

        rescued.cleanup_check_host_fence()

        assert "safe to clean the blocklist" in output.getvalue()

    @pytest.mark.parametrize("answer", ["1", "power off"])
    def test_powering_off_then_rechecking(self, gate, answer):
        rescued = gate(power_states=[False, True], answers=[answer])

        rescued.cleanup_check_host_fence()

        assert rescued._ipmi.commands == [("change", "power", "off")]

    @pytest.mark.parametrize("answer", ["0", "continue"])
    def test_overriding_needs_a_second_confirmation(self, gate, answer):
        rescued = gate(power_states=[False], answers=[answer], confirms=[True])

        rescued.cleanup_check_host_fence()

        assert rescued._ipmi.commands == []

    def test_refusing_the_confirmation_keeps_asking(self, gate):
        """Declining must not fall through to the blocklist cleanup."""
        rescued = gate(
            power_states=[False, False, True],
            answers=["0", "1"],
            confirms=[False],
        )

        rescued.cleanup_check_host_fence()

        # It came back round and only left once the host was really off.
        assert rescued._ipmi.commands == [("change", "power", "off")]
        assert rescued._ipmi.power_states == []


class TestMenuFallthroughs:
    """The answers that only re-check, and the errors that must not escape."""

    @pytest.mark.parametrize("answer", ["4", "check", "anything else"])
    def test_ensure_host_offline_rechecks_without_touching_the_host(
        self, gate, answer
    ):
        """The default answer just looks again."""
        rescued = gate(power_states=[False, True], answers=[answer])

        rescued.ensure_host_offline()

        assert rescued._ipmi.commands == []
        assert rescued._ipmi.power_states == []

    def test_forgetting_the_password_re_asks_for_it(self, gate):
        rescued = gate(power_states=[False, True], answers=["5"])
        rescued._ipmi.password = "stale"

        rescued.ensure_host_offline()

        assert rescued._ipmi.password == ""

    @pytest.mark.parametrize("answer", ["2", "check", "anything else"])
    def test_host_fence_rechecks_without_touching_the_host(self, gate, answer):
        rescued = gate(power_states=[False, True], answers=[answer])

        rescued.cleanup_check_host_fence()

        assert rescued._ipmi.commands == []
        assert rescued._ipmi.power_states == []

    def test_a_bmc_error_is_shown_and_the_gate_stays_open(self, gate, output):
        """A flaky BMC must not drop the operator past the fence check."""
        rescued = gate(
            power_states=[False, False, True],
            answers=["1", "1"],
            fail_on=[("power", "off")],
        )

        rescued.cleanup_check_host_fence()

        assert len(rescued._ipmi.commands) == 2
        assert "Command" in output.getvalue()
