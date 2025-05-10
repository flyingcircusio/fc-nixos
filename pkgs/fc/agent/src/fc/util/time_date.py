import datetime

import pytz


def ensure_timezone_present(dt: datetime.datetime):
    if dt and not dt.tzinfo:
        return pytz.UTC.localize(dt)

    return dt


def utcnow():
    return pytz.UTC.localize(datetime.datetime.utcnow())


def format_datetime(dt: datetime.datetime):
    if dt:
        return dt.strftime("%Y-%m-%d %H:%M UTC")
