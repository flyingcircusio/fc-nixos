from fc.manage.spread import Spread
from freezegun import freeze_time


def test_read_offset(tmpdir):
    (tmpdir / "stamp").write_text("34", "ascii")
    s = Spread(str(tmpdir / "stamp")).configure()
    assert s.offset == 34


def test_generate_offset(tmpdir):
    s = Spread(str(tmpdir / "stamp")).configure()
    assert "{}\n".format(s.offset) == (tmpdir / "stamp").read_text("ascii")


def test_no_offset(tmpdir):
    (tmpdir / "stamp").write_text("0", "ascii")
    s = Spread(str(tmpdir / "stamp")).configure()
    # due @ 1513591200 == 10:00:00
    (tmpdir / "stamp").setmtime(1513591200 - 10)
    with freeze_time("2017-12-18 09:59:59"):
        assert s.next_due() == 1513591200
        assert s.is_due() is False
    with freeze_time("2017-12-18 10:00:01"):
        assert s.is_due() is True  # touches file
        assert s.next_due() == 1513591200 + 7200
        assert (tmpdir / "stamp").mtime() == 1513591201


def test_with_offset(tmpdir):
    (tmpdir / "stamp").write_text("30", "ascii")
    s = Spread(str(tmpdir / "stamp")).configure()
    # due @ 1513591230 == 10:00:30
    (tmpdir / "stamp").setmtime(1513591200 - 10)
    with freeze_time("2017-12-18 10:00:29"):
        assert s.next_due() == 1513591230
        assert s.is_due() is False
    with freeze_time("2017-12-18 10:00:31"):
        assert s.is_due() is True  # touches file
        assert s.next_due() == 1513591230 + 7200
        assert (tmpdir / "stamp").mtime() == 1513591201  # offset subtracted
