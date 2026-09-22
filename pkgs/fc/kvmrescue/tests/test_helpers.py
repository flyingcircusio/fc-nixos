"""The small pure helpers, and the output rules that protect them."""

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


@pytest.mark.parametrize(
    ("status", "expected"),
    [
        (("kvm02", True, True), "✓ a@kvm02"),
        (("kvm02", False, False), "P a@kvm02"),
        (("", True, False), "L a"),
        (("", False, False), "LP a"),
    ],
)
def test_vm_cell_shapes(status, expected):
    locker, pings, healthy = status
    cell = rescue.vm_cell(rescue.VmStatus("a", locker, pings, healthy))
    assert cell.plain == expected


def test_vm_cell_marks_up_the_lock_holder():
    """`Text()` would print the tags; only `from_markup` styles them."""
    cell = rescue.vm_cell(rescue.VmStatus("a", "kvm02", True, True))
    assert "[grey50]" not in cell.plain
    assert [str(span.style) for span in cell.spans] == ["grey50"]


def vm_fleet(size=200, unhealthy=(7, 150)):
    fleet = [
        rescue.VmStatus(f"vm{i:03}", "kvm02", True, True) for i in range(size)
    ]
    for index in unhealthy:
        fleet[index] = rescue.VmStatus(f"vm{index:03}", "", False, False)
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
