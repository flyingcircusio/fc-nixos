import datetime

import pytz


def utcnow():
    return pytz.UTC.localize(datetime.datetime.utcnow())


def format_datetime(dt):
    return dt.strftime("%Y-%m-%d %H:%M UTC")
