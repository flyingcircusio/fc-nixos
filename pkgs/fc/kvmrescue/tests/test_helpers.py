"""The small pure helpers, and the output rules that protect them."""

import json
import re

import pytest
from rich.console import Console

import fc_kvmrescue as rescue


@pytest.mark.parametrize(
    ("entity_addr", "expected"),
    [
        ("172.20.4.101:0/3733721661", "172.20.4.101:0/0"),
        ("[2a02:238:f030::1053]:0/12", "[2a02:238:f030::1053]:0/0"),
        ("[fe80::1]:0/0", "[fe80::1]:0/0"),
        ("v1:172.20.4.101:6800/12", "172.20.4.101:0/0"),
        ("v2:[dead::1]:6800/12", "[dead::1]:0/0"),
    ],
)
def test_blocklist_address_covers_whole_client(entity_addr, expected):
    assert rescue.blocklist_address(entity_addr) == expected


def test_blocklist_address_rejects_nonsense():
    with pytest.raises(ValueError, match="not a Ceph EntityAddr"):
        rescue.blocklist_address("not-an-address")


@pytest.mark.parametrize(
    ("image", "expected"),
    [
        ("rbd.hdd/test00.root", "test00"),
        ("rbd.ssd/test00.swap", "test00"),
        ("rbd.hdd/vm-alpha.tmp", "vm-alpha"),
        # the pool's own dot must not be mistaken for a volume suffix
        ("rbd.hdd/noSuffix", "noSuffix"),
        # only the last suffix goes, so a dotted VM name survives
        ("rbd.hdd/test.example.com.root", "test.example.com"),
    ],
)
def test_vm_name_folds_volumes_onto_their_vm(image, expected):
    assert rescue.vm_name(image) == expected


@pytest.mark.parametrize(
    "message",
    [
        "address [fe80::1]:0/0 was blocklisted",
        "- [x] add_ticket_text",
        "rbd.hdd/test00.root",
    ],
)
def test_say_takes_brackets_literally(output, message):
    """rich would read `[fe80::1]` or `[x]` as markup and drop it."""
    rescue.say(message)
    assert message in output.getvalue()


def test_progress_bar_keeps_ipv6_addresses(output):
    bar = rescue.progress_bar()
    bar.live.console = rescue.console
    with bar:
        bar.add_task("Blocklisting", total=1, item="[fe80::1]:0/0")
    assert "[fe80::1]:0/0" in output.getvalue()


def spans(cell):
    """Every styled run of a cell, as (substring, style)."""
    return [(cell.plain[s.start : s.end], str(s.style)) for s in cell.spans]


def status(name="a", **fields):
    return rescue.VmStatus(name, **fields)


@pytest.mark.parametrize(
    ("locker", "expected"),
    [("kvm02", "LP a@kvm02"), ("", "LP a")],
)
def test_a_cell_reads_lock_ping_name_holder(locker, expected):
    """Both checks are always shown; the colour is what reports them."""
    assert rescue.vm_cell(status(locker=locker)).plain == expected


@pytest.mark.parametrize(
    ("new_locker", "pings", "lock_style", "ping_style"),
    [
        (True, True, "green", "green"),
        (True, False, "green", "yellow"),
        (False, True, "yellow", "green"),
        (False, False, "yellow", "yellow"),
    ],
)
def test_lock_and_ping_are_coloured_apart(
    new_locker, pings, lock_style, ping_style
):
    """Which of the two checks is missing has to be readable at a glance."""
    cell = rescue.vm_cell(status(new_locker=new_locker, pings=pings))
    assert spans(cell)[:2] == [("L", lock_style), ("P", ping_style)]


@pytest.mark.parametrize(
    ("new_locker", "pings", "expected"),
    [(True, True, "green"), (True, False, "yellow"), (False, True, "yellow")],
)
def test_the_name_is_green_only_when_the_vm_is_back(
    new_locker, pings, expected
):
    cell = rescue.vm_cell(status(new_locker=new_locker, pings=pings))
    assert ("a", expected) in spans(cell)


def test_the_lock_holder_is_dimmed():
    """It is context, not status, so it must not compete with the colours."""
    cell = rescue.vm_cell(status(locker="kvm02"))
    assert ("@kvm02", "grey50") in spans(cell)


def test_the_name_links_to_the_directory():
    cell = rescue.vm_cell(status(locker="kvm02"))
    assert ("a", f"link {rescue.directory_url('a')}") in spans(cell)


def test_a_check_in_flight_overrides_every_colour():
    """Only the link survives; every status colour turns into the marker."""
    cell = rescue.vm_cell(
        status(locker="kvm02", new_locker=True, pings=True, checking=True)
    )
    colours = {
        style for _, style in spans(cell) if not style.startswith("link ")
    }
    assert colours == {"blink2 deep_sky_blue1"}


def vm_fleet(size=200, unhealthy=(7, 150)):
    fleet = [
        rescue.VmStatus(f"vm{i:03}", "kvm02", new_locker=True, pings=True)
        for i in range(size)
    ]
    for index in unhealthy:
        fleet[index] = rescue.VmStatus(f"vm{index:03}")
    return fleet


def test_vm_overview_puts_unhealthy_first(output):
    rescue.console.print(rescue.vm_overview(vm_fleet()))
    first_line = output.getvalue().splitlines()[0]
    assert "vm007" in first_line and "vm150" in first_line


def test_vm_overview_trims_to_the_terminal(output):
    """200 VMs must not scroll a 20-line terminal away."""
    rescue.console.print(rescue.vm_overview(vm_fleet()))
    rendered = output.getvalue()
    assert re.search(r"… \d+ more", rendered)
    assert len([line for line in rendered.splitlines() if line.strip()]) <= 13


def test_vm_overview_shows_everything_when_it_fits(monkeypatch, output):
    monkeypatch.setattr(
        rescue,
        "console",
        Console(file=output, force_terminal=False, width=200, height=60),
    )
    rescue.console.print(rescue.vm_overview(vm_fleet()))
    assert not re.search(r"… \d+ more", output.getvalue())


def test_checkbox():
    assert rescue.checkbox("done", checked=True) == "- [x] done"
    assert rescue.checkbox("open") == "- [ ] open"


class TestOutputHelpers:
    """The small print helpers everything else is built out of."""

    def test_separator_spans_the_width(self, output):
        rescue.separator()
        assert output.getvalue().strip() == "=" * 80

    def test_framed_sets_a_block_off_for_copying(self, output):
        rescue.framed("copy me")
        lines = [
            line for line in output.getvalue().splitlines() if line.strip()
        ]
        assert lines[0] == "=" * 80
        assert lines[1] == "copy me"
        assert lines[2] == "=" * 80

    def test_divider_closes_a_step_with_a_rule(self, output):
        rescue.divider()
        printed = output.getvalue()
        assert "-" * 80 in printed
        assert printed.startswith("\n") and printed.endswith("\n\n")

    def test_heading_opens_a_block_with_a_blank_line(self, output):
        rescue.heading("Next up")
        assert output.getvalue() == "\nNext up\n"

    def test_show_link_indents_the_url(self, output):
        rescue.show_link("https://example.invalid/x")
        assert "https://example.invalid/x" in output.getvalue()

    @pytest.mark.parametrize(
        ("builder", "argument", "expected"),
        [
            (
                rescue.ticket_url,
                "PL-135552",
                "https://yt.flyingcircus.io/issue/PL-135552",
            ),
            (
                rescue.directory_url,
                "kvm05",
                "https://directory.fcio.net/machine/list?search=name-kvm05",
            ),
        ],
    )
    def test_urls(self, builder, argument, expected):
        assert builder(argument) == expected


class TestConfirm:
    """Anything that discards state must not be answerable by Enter alone."""

    @pytest.fixture
    def asked(self, monkeypatch):
        calls = []

        def ask(question, **kwargs):
            calls.append((question, kwargs))
            return True

        monkeypatch.setattr(rescue.Confirm, "ask", ask)
        return calls

    def test_without_a_default_no_default_is_passed_on(self, asked):
        assert rescue.confirm("Ready?") is True
        assert asked == [("Ready?", {})]

    @pytest.mark.parametrize("default", [True, False])
    def test_a_default_is_handed_through(self, asked, default):
        rescue.confirm("Ready?", default=default)
        assert asked == [("Ready?", {"default": default})]

    def test_a_question_is_set_off_from_the_output_above(self, asked, output):
        rescue.confirm("Ready?")
        assert output.getvalue() == "\n"

    def test_acknowledge_keeps_asking_until_yes(self, monkeypatch):
        answers = iter([False, False, True])
        asked = []

        monkeypatch.setattr(
            rescue,
            "confirm",
            lambda question: asked.append(question) or next(answers),
        )

        rescue.acknowledge("Done?")

        assert asked == ["Done?"] * 3


def test_list_locks_parses_rbd_output(fake_run):
    fake_run(
        {
            "lock ls": json.dumps(
                [
                    {
                        "id": "kvm05",
                        "locker": "client.1",
                        "address": "172.20.4.101:0/111",
                    }
                ]
            )
        }
    )

    locks = rescue.list_locks("rbd.hdd/test00.root")

    assert [lock.id for lock in locks] == ["kvm05"]
    assert locks[0].address == "172.20.4.101:0/111"
