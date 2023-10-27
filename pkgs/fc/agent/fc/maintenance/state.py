import enum


class State(enum.Enum):
    pending = "-"
    due = "*"
    running = "="
    success = "s"
    error = "e"
    deleted = "d"
    postpone = "p"

    def __str__(self):
        return self.name

    def __lt__(self, other):
        """Arbitrary sort order. It sufficient to have a sort order at all."""
        return self.name < other.name

    def valid_state(str):
        try:
            State(str)
        except ValueError:
            return False
        return True

    @property
    def short(self):
        """Single-letter representation."""
        return self.value


ARCHIVE = {State.success, State.error, State.deleted}

EXIT_SUCCESS = 0
EXIT_POSTPONE = 69
EXIT_TEMPFAIL = 75
EXIT_INTERRUPTED = 80


def evaluate_state(returncode):
    if returncode == EXIT_SUCCESS:
        return State.success
    if returncode == EXIT_TEMPFAIL:
        return State.due
    if returncode == EXIT_POSTPONE:
        return State.postpone
    return State.error
