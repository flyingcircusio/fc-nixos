# This file is dual licensed under the terms of the Apache License, Version
# 2.0, and the MIT License.  See the LICENSE file in the root of this
# repository for complete details.

from datetime import datetime
import io
import json
import os
import string
import structlog
import sys
import syslog

try:
    import colorama
except ImportError:
    colorama = None

try:
    import systemd.journal as journal
except ImportError:
    journal = None

_MISSING = "{who} requires the {package} package installed."
_EVENT_WIDTH = 30  # pad the event name to so many characters

if sys.stdout.isatty() and colorama:
    RESET_ALL = colorama.Style.RESET_ALL
    BRIGHT = colorama.Style.BRIGHT
    DIM = colorama.Style.DIM
    RED = colorama.Fore.RED
    BACKRED = colorama.Back.RED
    BLUE = colorama.Fore.BLUE
    CYAN = colorama.Fore.CYAN
    MAGENTA = colorama.Fore.MAGENTA
    YELLOW = colorama.Fore.YELLOW
    GREEN = colorama.Fore.GREEN
else:
    RESET_ALL = ''
    BRIGHT = ''
    DIM = ''
    RED = ''
    BACKRED = ''
    BLUE = ''
    CYAN = ''
    MAGENTA = ''
    YELLOW = ''
    GREEN = ''


class PartialFormatter(string.Formatter):
    """
    A string formatter that doesn't break if values are missing or formats are wrong.
    Missing values and bad formats are replaced by a fixed string that can be set
    when constructing an formatter object.

    formatter = PartialFormatter(missing='<missing>', bad_format='<bad format'>)
    formatted_str = formatter.format("{exists} {missing}", exists=1)
    formatted_str == "1 <missing>"
    """

    def __init__(self, missing='<missing>', bad_format='<bad format>'):
        self.missing = missing
        self.bad_format = bad_format

    def get_field(self, field_name, args, kwargs):
        try:
            val = super().get_field(field_name, args, kwargs)
        except (KeyError, AttributeError):
            val = (None, field_name)
        return val

    def format_field(self, value, format_spec):
        if value is None:
            return self.missing
        try:
            return super().format_field(value, format_spec)
        except ValueError:
            self.bad_format


class MultiOptimisticLoggerFactory:

    def __init__(self, **factories):
        self.factories = factories

    def __call__(self, *args):
        loggers = {k: f() for k, f in self.factories.items()}
        return MultiOptimisticLogger(loggers)


class MultiOptimisticLogger:
    """
    A logger which distributes messages to multiple loggers.
    It's initialized with a logger dict where the keys are the logger names
    which correspond to the keyword arguments given to the msg method.
    If the logger's name is not present in the arguments, the logger is skipped.
    Errors in sub loggers are ignored silently.
    """

    def __init__(self, loggers):
        self.loggers = loggers

    def __repr__(self):
        return '<MultiOptimisticLogger {}>'.format(
            [repr(l) for l in self.loggers])

    def msg(self, **messages):
        for name, logger in self.loggers.items():
            try:
                line = messages.get(name)
                if line:
                    logger.msg(line)
            except Exception:
                # We're being really optimistic: we want the calling program
                # to continue even if we face huge troubles logging stuff.
                pass

    def __getattr__(self, name):
        return self.msg


class DummyJournalLogger:

    def msg(self, message):
        pass


class JournalLogger:

    def msg(self, message):
        journal.send(**message)


class JournalLoggerFactory:

    def __init__(self):

        if journal is None:
            print(
                _MISSING.format(
                    who=self.__class__.__name__, package="systemd"))

    def __call__(self, *args):
        if journal is None:
            return DummyJournalLogger()
        else:
            return JournalLogger()


class CmdOutputFileRenderer:

    def __call__(self, logger, method_name, event_dict):

        line = event_dict.pop('cmd_output_line', None)
        if line is not None:
            return {'cmd_output_file': line}
        else:
            return {}


def prefix(prefix, line):
    return '{}>\t'.format(prefix) + line.replace('\n',
                                                 '\n{}>\t'.format(prefix))


def _pad(s, l):
    """
    Pads *s* to length *l*.
    """
    missing = l - len(s)
    return s + " " * (missing if missing > 0 else 0)


class ConsoleFileRenderer:
    """
    Render `event_dict` nicely aligned, in colors, and ordered with
    specific knowledge about fc.agent structures.
    """

    LEVELS = [
        'alert', 'critical', 'error', 'warn', 'warning', 'info', 'debug',
        'trace'
    ]

    def __init__(self,
                 min_level,
                 show_caller_info=False,
                 pad_event=_EVENT_WIDTH):
        self.min_level = self.LEVELS.index(min_level.lower())
        self.show_caller_info = show_caller_info
        if colorama is None:
            print(
                _MISSING.format(
                    who=self.__class__.__name__, package="colorama"))
        if sys.stdout.isatty():
            colorama.init()

        self._pad_event = pad_event
        self._level_to_color = {
            "alert": RED,
            "critical": RED,
            "error": RED,
            "warn": YELLOW,
            "warning": YELLOW,
            "info": GREEN,
            "debug": GREEN,
            "trace": GREEN,
            "notset": BACKRED,
        }
        for key in self._level_to_color.keys():
            self._level_to_color[key] += BRIGHT
        self._longest_level = len(
            max(self._level_to_color.keys(), key=lambda e: len(e)))

    def __call__(self, logger, method_name, event_dict):
        console_io = io.StringIO()
        log_io = io.StringIO()

        def write(line):
            console_io.write(line)
            if RESET_ALL:
                for SYMB in [
                        RESET_ALL, BRIGHT, DIM, RED, BACKRED, BLUE, CYAN,
                        MAGENTA, YELLOW, GREEN
                ]:
                    line = line.replace(SYMB, '')
            log_io.write(line)

        replace_msg = event_dict.pop("_replace_msg", None)
        if replace_msg:
            formatter = PartialFormatter()
            formatted_replace_msg = formatter.format(replace_msg, **event_dict)
        else:
            formatted_replace_msg = None

        if not self.show_caller_info:
            event_dict.pop('code_file', None)
            event_dict.pop('code_func', None)
            event_dict.pop('code_lineno', None)
            event_dict.pop('code_module', None)

        ts = event_dict.pop("timestamp", None)
        if ts is not None:
            write(
                # can be a number if timestamp is UNIXy
                DIM + str(ts) + RESET_ALL + " ")

        event_dict.pop("pid", None)

        level = event_dict.pop("level", None)
        if level is not None:
            write(self._level_to_color[level] + level[0].upper() + RESET_ALL +
                  ' ')

        event = event_dict.pop("event")
        write(BRIGHT + _pad(event, self._pad_event) + RESET_ALL + " ")

        logger_name = event_dict.pop("logger", None)
        if logger_name is not None:
            write("[" + BLUE + BRIGHT + logger_name + RESET_ALL + "] ")

        cmd_output_line = event_dict.pop("cmd_output_line", None)
        stdout = event_dict.pop("stdout", None)
        stderr = event_dict.pop("stderr", None)
        stack = event_dict.pop("stack", None)
        exception_traceback = event_dict.pop("exception_traceback", None)

        if formatted_replace_msg:
            write(formatted_replace_msg)
        else:
            write(" ".join(CYAN + key + RESET_ALL + "=" + MAGENTA +
                           repr(event_dict[key]) + RESET_ALL
                           for key in sorted(event_dict.keys())))

        if cmd_output_line is not None:
            write(DIM + "> " + cmd_output_line + RESET_ALL)

        if stdout is not None:
            write('\n' + DIM + prefix("out", "\n" + stdout + "\n") + RESET_ALL)

        if stderr is not None:
            write('\n' + prefix("err", "\n" + stderr + "\n") + RESET_ALL)

        if stack is not None:
            write("\n" + prefix("stack", stack))
            if exception_traceback is not None:
                write("\n" + "=" * 79 + "\n")

        if exception_traceback is not None:
            write("\n" + prefix("exception", exception_traceback))

        # Filter according to the -v switch when outputting to the
        # console.
        if self.LEVELS.index(method_name.lower()) > self.min_level:
            console_io.seek(0)
            console_io.truncate()

        message = {'console': console_io.getvalue(), 'file': log_io.getvalue()}
        return message


class MultiRenderer:
    """
    Calls multiple renderers with a shallow copy of the event dict and collects
    their messages in a dict with the renderer names as keys and their
    rendered output as values. It doesn't care about the rendered messages
    so different logger types can get different types of messages.
    Normally, this should be placed last in the processors chain.
    Errors in renderers are ignored silently.
    """

    def __init__(self, **renderers):
        self.renderers = renderers

    def __repr__(self):
        return '<MultiRenderer {}>'.format([repr(l) for l in self.renderers])

    def __call__(self, logger, method_name, event_dict):
        merged_messages = {}
        for renderer in self.renderers.values():
            try:
                messages = renderer(logger, method_name, event_dict.copy())
                merged_messages.update(messages)
            except Exception:
                # We're being really optimistic: we want the calling program
                # to continue even if we face huge troubles logging stuff.
                pass

        return merged_messages


def add_pid(logger, method_name, event_dict):
    event_dict['pid'] = os.getpid()
    return event_dict


def add_caller_info(logger, method_name, event_dict):
    frame, module_str = structlog._frames._find_first_app_frame_and_name(
        additional_ignores=[__name__])
    event_dict['code_file'] = frame.f_code.co_filename
    event_dict['code_func'] = frame.f_code.co_name
    event_dict['code_lineno'] = frame.f_lineno
    event_dict['code_module'] = module_str
    return event_dict


def add_pid(logger, method_name, event_dict):
    event_dict['pid'] = os.getpid()
    return event_dict


JOURNAL_LEVELS = {
    'alert': syslog.LOG_ALERT,
    'critical': syslog.LOG_CRIT,
    'error': syslog.LOG_ERR,
    'warn': syslog.LOG_WARNING,
    'warning': syslog.LOG_WARNING,
    'info': syslog.LOG_INFO,
    'debug': syslog.LOG_DEBUG,
    'trace': syslog.LOG_DEBUG,
}

KEYS_TO_SKIP_IN_JOURNAL_MESSAGE = [
    "_replace_msg",
    "code_file",
    "code_func",
    "code_lineno",
    "code_module",
    "event",
    "exception_traceback",
    "invocation_id",
    "level",
    "message",
    "output",
    "pid",
    "timestamp",
]


class SystemdJournalRenderer:

    def __init__(self, syslog_identifier, syslog_facility=syslog.LOG_LOCAL0):
        self.syslog_identifier = syslog_identifier
        self.syslog_facility = syslog_facility

    def __call__(self, logger, method_name, event_dict):

        if method_name == 'trace':
            return {}

        kv_renderer = structlog.processors.KeyValueRenderer(sort_keys=True)
        event_dict["message"] = event_dict["event"]
        replace_msg = event_dict.pop("_replace_msg", None)

        if replace_msg is not None:
            formatter = PartialFormatter()
            formatted_replace_msg = formatter.format(replace_msg, **event_dict)
            event_dict["message"] += ": " + formatted_replace_msg
        else:

            kv = kv_renderer(
                None, None, {
                    k: v
                    for k, v in event_dict.items()
                    if k not in KEYS_TO_SKIP_IN_JOURNAL_MESSAGE
                })

            if kv:
                event_dict["message"] += ": " + kv

        event_dict.pop("timestamp", None)
        event_dict.pop("pid", None)
        code_lineno = event_dict.pop("code_lineno", None)

        event_dict = {
            k.upper(): self.dump_for_journal(v)
            for k, v in event_dict.items()
        }

        event_dict['PRIORITY'] = JOURNAL_LEVELS.get(
            event_dict.get("LEVEL"), syslog.LOG_INFO)
        event_dict['SYSLOG_FACILITY'] = self.syslog_facility
        event_dict['SYSLOG_IDENTIFIER'] = self.syslog_identifier
        event_dict['CODE_LINE'] = code_lineno

        return {"journal": event_dict}

    def handle_json_fallback(self, obj):
        """Same as structlog's json fallback.
        Supports obj.__structlog__() for custom object serialization.
        """
        try:
            return obj.__structlog__()
        except AttributeError:
            return repr(obj)

    def dump_for_journal(self, obj):
        """Encode values as JSON, except strings.
        We keep strings unchanged to display line breaks properly in journalctl
        and graylog.
        """
        if isinstance(obj, str):
            return obj
        elif isinstance(obj, datetime):
            return datetime.isoformat(obj)
        else:
            return json.dumps(obj, default=self.handle_json_fallback)


def process_exc_info(logger, name, event_dict):
    """Transforms exc_info to the exception tuple format returned by
    sys.exc_info(). Uses the the same logic as as structlog's format_exc_info()
    to unify the different types exc_info could contain but doesn't render
    the exception yet.
    """
    exc_info = event_dict.get("exc_info", None)

    if isinstance(exc_info, BaseException):
        event_dict["exc_info"] = (exc_info.__class__, exc_info,
                                  exc_info.__traceback__)
    elif isinstance(exc_info, tuple):
        pass
    elif exc_info:
        event_dict["exc_info"] = sys.exc_info()

    return event_dict


def format_exc_info(logger, name, event_dict):
    """Renders exc_info if it's present.
    Expects the tuple format returned by sys.exc_info().
    Compared to structlog's format_exc_info(), this renders the exception
    information separately which is better for structured logging targets.
    """
    exc_info = event_dict.pop("exc_info", None)
    if exc_info is not None:
        exception_class = exc_info[0]
        formatted_traceback = structlog.processors._format_exception(exc_info)
        event_dict["exception_traceback"] = formatted_traceback
        event_dict["exception_msg"] = str(exc_info[1])
        event_dict[
            "exception_class"] = exception_class.__module__ + "." + exception_class.__name__

    return event_dict


def init_logging(verbose, main_log_file=None, cmd_log_file=None):

    multi_renderer = MultiRenderer(
        journal=SystemdJournalRenderer("fc-agent", syslog.LOG_LOCAL1),
        cmd_output_file=CmdOutputFileRenderer(),
        text=ConsoleFileRenderer(
            min_level='debug' if verbose else 'info',
            show_caller_info=verbose))

    processors = [
        add_pid,
        structlog.processors.add_log_level,
        process_exc_info,
        format_exc_info,
        structlog.processors.StackInfoRenderer(),
        structlog.processors.TimeStamper(fmt='iso', utc=False),
        add_caller_info,
        multi_renderer,
    ]

    loggers = {}

    if cmd_log_file:
        loggers["cmd_output_file"] = structlog.PrintLoggerFactory(cmd_log_file)
    if main_log_file:
        loggers["file"] = structlog.PrintLoggerFactory(main_log_file)
    if journal:
        loggers["journal"] = JournalLoggerFactory()

    # If the journal module is available and stdout is connected to journal, we
    # shouldn't log to console because output would be duplicated in the journal.
    if journal and not os.environ.get("JOURNAL_STREAM"):
        loggers["console"] = structlog.PrintLoggerFactory()

    structlog.configure(
        processors=processors,
        wrapper_class=structlog.BoundLogger,
        logger_factory=MultiOptimisticLoggerFactory(**loggers))
