import datetime
import pytest
import syslog

try:
    from systemd import journal
except ImportError:
    journal = None

from fc.util.logging import JournalLoggerFactory, JournalLogger, SystemdJournalRenderer


@pytest.mark.skipif(journal is None, reason='systemd package not available')
def test_journal_logger():
    factory = JournalLoggerFactory()
    logger = factory()
    assert isinstance(logger, JournalLogger)


@pytest.fixture
def journald_renderer():
    return SystemdJournalRenderer("test")


def test_journal_renderer(journald_renderer):
    event_dict = {
        "event": "test-event",
        "pid": 123,
        "timestamp": 1000000,
        "code_lineno": 2,
        "code_file": "file",
        "code_func": "func",
        "output": "output",
        "code_module": "module",
        "bool_var": True,
        "level": "debug",
        "none": None,
        "emptystring": "",
        "a_list": ["a", "b"],
        "a_tuple": ("a", "b"),
        "a_dict": dict(a=1, b=2),
        "multiline": "multi\nline"
    }

    message = (
        "test-event: a_dict={'a': 1, 'b': 2} a_list=['a', 'b'] a_tuple=('a', 'b') "
        + "bool_var=True emptystring='' multiline='multi\\nline' none=None")

    expected_journal_msg = {
        "SYSLOG_IDENTIFIER": "test",
        "SYSLOG_FACILITY": syslog.LOG_LOCAL0,
        "EVENT": "test-event",
        "CODE_LINE": 2,
        "CODE_FILE": "file",
        "CODE_FUNC": "func",
        "OUTPUT": "output",
        "CODE_MODULE": "module",
        "EMPTYSTRING": "",
        "LEVEL": "debug",
        "MESSAGE": message,
        "PRIORITY": syslog.LOG_DEBUG,
        "A_DICT": '{"a": 1, "b": 2}',
        "A_TUPLE": '["a", "b"]',
        "A_LIST": '["a", "b"]',
        "NONE": "null",
        "BOOL_VAR": "true",
        "MULTILINE": "multi\nline"
    }

    rendered = journald_renderer(None, None, event_dict)
    assert "journal" in rendered
    assert rendered["journal"] == expected_journal_msg


def test_journal_renderer_replace_msg(journald_renderer):
    event_dict = {
        "event": "test-event",
        "pid": 123,
        "_replace_msg": "test msg with pid {pid}"
    }

    rendered = journald_renderer(None, None, event_dict)
    assert "journal" in rendered
    assert rendered["journal"][
        "MESSAGE"] == "test-event: test msg with pid 123"
