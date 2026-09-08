import os
from datetime import datetime
from pathlib import Path
from typing import Self

from pydantic import BaseModel

STATE_FILE_PATH = Path.home() / Path(".local/state/fc-kvmrescue/state.json")


class RescueState(BaseModel):
    creation_date: datetime

    @classmethod
    def ensure_statefile(cls) -> Self:
        try:
            # XXX: warn and prompt on existing file, option to move aside
            return cls.model_validate_json(STATE_FILE_PATH.read_text())
        except FileNotFoundError:
            STATE_FILE_PATH.parent.mkdir(parents=True, exist_ok=True)
            state = cls(creation_date=datetime.now())
            _ = STATE_FILE_PATH.write_text(state.model_dump_json())
        return state
