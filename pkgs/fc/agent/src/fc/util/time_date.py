from datetime import UTC, datetime


def ensure_timezone_present(dt: datetime):
    """timezone-naive datetime objects are made implicitly UTC,
    others with an explicitly specified timezone are passed through"""
    if dt and not dt.tzinfo:
        return dt.astimezone(UTC)

    return dt


def utcnow():
    return datetime.now(tz=UTC)


def format_datetime(dt: datetime):
    if dt:
        return dt.strftime("%Y-%m-%d %H:%M UTC")
