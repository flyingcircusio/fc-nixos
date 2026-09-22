"""The cleanup half of the rescue, and the operator prompts it hangs on."""

import subprocess

import pytest

import fc_kvmrescue as rescue


class TestIsPoweredOff:
    def _ipmi(self, monkeypatch, answer):
        ipmi = rescue.Ipmi("kvm05", "ADMIN")
        if isinstance(answer, Exception):
            monkeypatch.setattr(
                ipmi, "run", lambda *a: (_ for _ in ()).throw(answer)
            )
        else:
            monkeypatch.setattr(ipmi, "run", lambda *a: answer)
        return ipmi

    def test_reports_a_powered_down_host(self, monkeypatch, output):
        ipmi = self._ipmi(monkeypatch, "Chassis Power is off\n")
        assert ipmi.is_powered_off() is True
        assert "Power is off." in output.getvalue()

    def test_reports_any_other_status(self, monkeypatch, output):
        ipmi = self._ipmi(monkeypatch, "Chassis Power is on\n")
        assert ipmi.is_powered_off() is False
        assert "Chassis Power is on" in output.getvalue()

    def test_an_unreachable_bmc_is_not_proof_of_being_off(
        self, monkeypatch, output
    ):
        """The dangerous answer would be True, so it must report False."""
        error = subprocess.CalledProcessError(1, ["fc-ipmitool"])
        ipmi = self._ipmi(monkeypatch, error)

        assert ipmi.is_powered_off() is False
        assert "Error calling ipmitool" in output.getvalue()


class TestCleanupStart:
    def test_continuing_falls_through(self, monkeypatch, make_state):
        monkeypatch.setattr(rescue, "confirm", lambda *a, **k: True)
        rescue.Rescue(make_state()).cleanup_start()

    def test_declining_interrupts_the_rescue(self, monkeypatch, make_state):
        """The operator gets to stop after the evacuation and resume later."""
        monkeypatch.setattr(rescue, "confirm", lambda *a, **k: False)
        with pytest.raises(KeyboardInterrupt):
            rescue.Rescue(make_state()).cleanup_start()


class TestInvestigateWarnings:
    def test_says_so_when_there_is_nothing_to_look_at(self, make_state, output):
        rescue.Rescue(make_state()).investigate_warnings()
        assert "No warnings found." in output.getvalue()

    def test_repeats_the_warnings_and_waits(
        self, monkeypatch, make_state, output
    ):
        asked = []
        monkeypatch.setattr(
            rescue,
            "confirm",
            lambda question, **k: asked.append(question) or True,
        )
        state = make_state()
        state.warnings = ["rbd.hdd/a is locked by two hosts"]

        rescue.Rescue(state).investigate_warnings()

        assert "locked by two hosts" in output.getvalue()
        assert asked == ["Did you investigate all warnings above?"]


class TestBlocklistCleanup:
    @pytest.fixture
    def state(self, make_state):
        state = make_state()
        state.blocklist = ["172.20.4.101:0/0", "[fe80::1]:0/0"]
        return state

    def test_removes_every_entry(self, state, fake_run):
        calls = fake_run()

        rescue.Rescue(state).blocklist_cleanup()

        assert [call[-1] for call in calls] == state.blocklist

    def test_offers_a_manual_fallback_when_ceph_refuses(
        self, monkeypatch, state, output
    ):
        def refuse(cmd, *args, **kwargs):
            raise subprocess.CalledProcessError(1, cmd)

        monkeypatch.setattr(subprocess, "run", refuse)
        monkeypatch.setattr(rescue, "confirm", lambda *a, **k: True)

        rescue.Rescue(state).blocklist_cleanup()

        assert "manually on a ceph mon host" in output.getvalue()

    def test_reraises_when_the_operator_could_not_fix_it(
        self, monkeypatch, state
    ):
        """Blocklist entries left behind must not pass silently."""

        def refuse(cmd, *args, **kwargs):
            raise subprocess.CalledProcessError(1, cmd)

        monkeypatch.setattr(subprocess, "run", refuse)
        monkeypatch.setattr(rescue, "confirm", lambda *a, **k: False)

        with pytest.raises(subprocess.CalledProcessError):
            rescue.Rescue(state).blocklist_cleanup()


class TestOperatorTasks:
    @pytest.mark.parametrize(
        "step", ["set_out_of_service", "mark_nonprod", "set_back_in_service"]
    )
    def test_each_shows_the_directory_and_waits(
        self, monkeypatch, make_state, output, step
    ):
        asked = []
        monkeypatch.setattr(
            rescue,
            "confirm",
            lambda question, **k: asked.append(question) or True,
        )

        getattr(rescue.Rescue(make_state()), step)()

        assert rescue.directory_url("kvm05") in output.getvalue()
        assert len(asked) == 1


def test_report_warnings_stays_quiet_without_any(make_state, output):
    rescue.report_warnings(make_state())
    assert output.getvalue() == ""


def test_report_warnings_sorts_them(make_state, output):
    state = make_state()
    state.warnings = ["zebra", "alpha"]

    rescue.report_warnings(state)

    printed = output.getvalue()
    assert printed.index("alpha") < printed.index("zebra")
