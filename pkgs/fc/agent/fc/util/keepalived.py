from datetime import datetime
from enum import Enum
from pathlib import Path

KEEPALIVED_STATE_FILE = Path("/run/keepalived/state")
MAINT_MARKER_FILE = Path("/etc/keepalived/fcio_maintenance")


class KeepalivedState(Enum):
    MASTER = "master"
    BACKUP = "backup"
    FAULT = "fault"
    STOP = "stop"


class KeepalivedStateError(Exception):
    pass


def get_state(log) -> KeepalivedState:
    if not KEEPALIVED_STATE_FILE.exists():
        log.error("keepalived-state-file-missing")
        raise KeepalivedStateError(
            f"Missing keepalive state file, expected at {KEEPALIVED_STATE_FILE}"
        )

    state_content = KEEPALIVED_STATE_FILE.read_text()
    state_last_modified = datetime.fromtimestamp(
        KEEPALIVED_STATE_FILE.stat().st_mtime
    )
    log.debug(
        "keepalived-state-file",
        content=state_content,
        last_modified=state_last_modified.isoformat(),
        path=str(KEEPALIVED_STATE_FILE),
    )

    if not MAINT_MARKER_FILE.exists():
        log.error("maintenance-marker-file-missing")
        raise KeepalivedStateError(
            f"Maintenance marker file missing, expected at {MAINT_MARKER_FILE}"
        )

    maint_file_content = MAINT_MARKER_FILE.read_text()

    maint_last_modified = datetime.fromtimestamp(
        MAINT_MARKER_FILE.stat().st_mtime
    )
    maint = int(maint_file_content)

    log.debug(
        "maintenance-marker-file",
        content=maint_file_content,
        last_modified=maint_last_modified.isoformat(),
        path=str(MAINT_MARKER_FILE),
    )

    try:
        state = KeepalivedState(state_content)
    except ValueError:
        log.error("unexpected-state-file-content", content=state_content)
        raise KeepalivedStateError(
            f"State file content is not a keepalived state: '{state_content}'"
        )
    log.debug("status", state=state, in_maintenance=maint > 0)

    return state
