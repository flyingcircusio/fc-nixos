"""The state file, and the host being the identity of a rescue."""

import fc_kvmrescue as rescue


def test_state_file_is_named_after_the_host(state_dir):
    state = rescue.new_state("kvm05")
    assert state.path == state_dir / "kvm05.json"


def test_a_new_rescue_has_no_ticket_yet():
    """register_ticket fills it in; open_state no longer asks."""
    assert rescue.new_state("kvm05").yt_ticket == ""


def test_round_trip_keeps_locks_and_warnings(make_state, lock):
    state = make_state("kvm05")
    state.locked_images = {"rbd.hdd/test00.root": [lock("kvm05")]}
    state.warn("something looked off")
    state.mark_done("collect_locks")

    reloaded = rescue.RescueState.load("kvm05")
    assert reloaded.locked_images == state.locked_images
    assert reloaded.warnings == ["something looked off"]
    assert reloaded.completed == ["collect_locks"]


def test_load_returns_none_without_a_state_file():
    assert rescue.RescueState.load("kvm99") is None


def test_warn_and_mark_done_do_not_duplicate(make_state):
    state = make_state()
    state.warn("once")
    state.warn("once")
    state.mark_done("collect_locks")
    state.mark_done("collect_locks")
    assert state.warnings == ["once"]
    assert state.completed == ["collect_locks"]


def test_locker_addresses_only_covers_the_dead_host(make_state, lock):
    state = make_state("kvm05")
    state.locked_images = {
        "rbd.hdd/a.root": [
            lock("kvm05", "172.20.4.101:0/111"),
            lock("kvm09", "172.20.4.109:0/9"),  # a foreign lock: not ours
        ],
        "rbd.ssd/b.root": [lock("kvm05", "[fe80::1]:0/333")],
        # the same address twice must collapse into one blocklist entry
        "rbd.ssd/c.root": [lock("kvm05", "172.20.4.101:0/222")],
    }
    assert state.locker_addresses == ["172.20.4.101:0/0", "[fe80::1]:0/0"]


class TestOneRescuePerHost:
    """The state file name is what stops a second, rival rescue."""

    def _reopen(self, monkeypatch, host, choice):
        """Answer the resume/new prompt open_state puts up."""
        monkeypatch.setattr(rescue.Prompt, "ask", lambda *a, **k: choice)
        monkeypatch.setattr(rescue, "list_steps", lambda rescued: None)
        return rescue.open_state(host)

    def test_second_run_resumes_the_same_rescue(
        self, monkeypatch, state_dir, make_state
    ):
        first = rescue.new_state("kvm05")
        first.yt_ticket = "PL-135552"
        first.save()

        again = self._reopen(monkeypatch, "kvm05", choice="resume")

        assert again.path == first.path
        assert again.yt_ticket == "PL-135552"
        assert [p.name for p in state_dir.glob("*.json")] == ["kvm05.json"]

    def test_each_host_gets_its_own_rescue(self, state_dir):
        rescue.new_state("kvm05")
        rescue.new_state("kvm09")
        assert sorted(p.name for p in state_dir.glob("*.json")) == [
            "kvm05.json",
            "kvm09.json",
        ]

    def test_starting_over_keeps_the_name_and_backs_up_the_old_run(
        self, monkeypatch, state_dir
    ):
        first = rescue.new_state("kvm05")
        first.yt_ticket = "PL-135552"
        first.completed = ["register_ticket"]
        first.save()

        fresh = self._reopen(monkeypatch, "kvm05", choice="new")

        assert fresh.path == state_dir / "kvm05.json"
        assert fresh.yt_ticket == ""
        assert fresh.completed == []
        # The previous run is kept aside rather than overwritten.
        assert (state_dir / "kvm05.json.0.bak").exists()

    def test_an_answer_it_does_not_know_asks_again(
        self, monkeypatch, state_dir
    ):
        """Nothing but resume or new gets past the prompt."""
        rescue.new_state("kvm05").save()
        answers = iter(["", "maybe", "resume"])
        monkeypatch.setattr(rescue.Prompt, "ask", lambda *a, **k: next(answers))
        monkeypatch.setattr(rescue, "list_steps", lambda rescued: None)

        state = rescue.open_state("kvm05")

        assert state.kvmhostname == "kvm05"
        assert next(answers, "exhausted") == "exhausted"

    def test_starting_over_twice_does_not_clobber_the_first_backup(
        self, monkeypatch, state_dir
    ):
        rescue.new_state("kvm05").save()
        self._reopen(monkeypatch, "kvm05", choice="new")
        self._reopen(monkeypatch, "kvm05", choice="new")

        assert (state_dir / "kvm05.json.0.bak").exists()
        assert (state_dir / "kvm05.json.1.bak").exists()


class TestRegisterTicket:
    def test_asks_once_and_persists(self, monkeypatch, make_state):
        state = make_state("kvm05")
        monkeypatch.setattr(rescue, "confirm", lambda *a, **k: True)
        monkeypatch.setattr(rescue.Prompt, "ask", lambda *a, **k: "PL-135552")

        rescue.Rescue(state).register_ticket()

        assert state.yt_ticket == "PL-135552"
        assert rescue.RescueState.load("kvm05").yt_ticket == "PL-135552"

    def test_does_not_ask_again_once_known(self, monkeypatch, make_state):
        state = make_state("kvm05", yt_ticket="PL-135552")

        def refuse(*args, **kwargs):
            raise AssertionError("asked for a ticket it already had")

        monkeypatch.setattr(rescue.Prompt, "ask", refuse)
        rescue.Rescue(state).register_ticket()

        assert state.yt_ticket == "PL-135552"

    def test_points_at_the_manual_when_there_is_no_ticket(
        self, monkeypatch, make_state, output
    ):
        linked = []
        monkeypatch.setattr(rescue, "show_link", linked.append)
        monkeypatch.setattr(rescue.Prompt, "ask", lambda *a, **k: "PL-1")

        rescue.Rescue(make_state()).register_ticket()

        assert "create a new ticket" in output.getvalue()
        assert linked == [rescue.MANUAL_URL]


class TestKnownRescues:
    def _rescue(self, host, *, ticket="", completed=(), minute=0):
        state = rescue.new_state(host)
        state.yt_ticket = ticket
        state.completed = list(completed)
        state.created = state.created.replace(minute=minute)
        state.save()
        return state

    def test_lists_nothing_when_there_is_nothing(self):
        assert rescue.known_rescues() == []

    def test_most_recent_first(self):
        self._rescue("kvm01", minute=1)
        self._rescue("kvm09", minute=9)
        self._rescue("kvm05", minute=5)

        assert [s.kvmhostname for s in rescue.known_rescues()] == [
            "kvm09",
            "kvm05",
            "kvm01",
        ]

    def test_a_restarted_rescue_leaves_one_entry(self, monkeypatch, state_dir):
        """A `.bak` backup must not show up as a second rescue."""
        self._rescue("kvm05")
        monkeypatch.setattr(rescue.Prompt, "ask", lambda *a, **k: "new")
        monkeypatch.setattr(rescue, "list_steps", lambda rescued: None)
        rescue.open_state("kvm05")

        assert (state_dir / "kvm05.json.0.bak").exists()
        assert [s.kvmhostname for s in rescue.known_rescues()] == ["kvm05"]

    def test_an_unreadable_file_does_not_block_a_new_rescue(
        self, state_dir, output
    ):
        self._rescue("kvm01")
        (state_dir / "broken.json").write_text("{not json")

        hosts = [s.kvmhostname for s in rescue.known_rescues()]

        assert hosts == ["kvm01"]
        assert "Ignoring unreadable state file" in output.getvalue()

    def test_shows_the_last_completed_step(self, output):
        self._rescue(
            "kvm05",
            ticket="PL-135552",
            completed=["register_ticket", "collect_locks"],
        )

        rescue.show_known_rescues()

        printed = output.getvalue()
        assert "kvm05" in printed
        assert "PL-135552" in printed
        assert rescue.Rescue.all_steps()["collect_locks"].description in printed

    def test_marks_a_rescue_that_has_not_started(self, output):
        self._rescue("kvm05")

        rescue.show_known_rescues()

        assert "nothing yet" in output.getvalue()

    def test_stays_quiet_with_no_state_files(self, output):
        rescue.show_known_rescues()
        assert output.getvalue() == ""


class TestOpenStatePrompting:
    def test_lists_what_is_running_before_asking(self, monkeypatch, output):
        rescue.new_state("kvm09").save()
        monkeypatch.setattr(rescue.Prompt, "ask", lambda *a, **k: "kvm05")

        rescue.open_state(None)

        assert "Rescues in progress" in output.getvalue()
        assert "kvm09" in output.getvalue()

    def test_does_not_list_when_the_host_was_given(self, monkeypatch, output):
        """Naming a host is unambiguous, so the table would only be noise."""
        rescue.new_state("kvm09").save()
        output.truncate(0)
        output.seek(0)

        rescue.open_state("kvm05")

        assert "Rescues in progress" not in output.getvalue()
