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

    def _resume(self, monkeypatch, host, answer):
        monkeypatch.setattr(rescue, "confirm", lambda *a, **k: answer)
        monkeypatch.setattr(rescue, "list_steps", lambda state: None)
        return rescue.open_state(host)

    def test_second_run_resumes_the_same_rescue(
        self, monkeypatch, state_dir, make_state
    ):
        first = rescue.new_state("kvm05")
        first.yt_ticket = "PL-135552"
        first.save()

        again = self._resume(monkeypatch, "kvm05", answer=True)

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

    def test_declining_archives_and_reuses_the_host_name(
        self, monkeypatch, state_dir
    ):
        rescue.new_state("kvm05").save()

        fresh = self._resume(monkeypatch, "kvm05", answer=False)

        assert fresh.path == state_dir / "kvm05.json"
        assert fresh.yt_ticket == ""
        assert (state_dir / "kvm05.old.json").exists()


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


def test_ticket_template_lists_every_step(make_state):
    state = make_state()
    state.completed = ["register_ticket"]
    state.warnings = ["look at this"]

    template = rescue.ticket_template(state)

    assert "- [x] Register rescue ticket" in template
    assert "- [ ] Find affected RBD images" in template
    assert "- [ ] look at this" in template
