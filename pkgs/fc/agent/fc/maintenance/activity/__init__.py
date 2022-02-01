"""Base class for maintenance activities."""
from enum import Enum
from typing import NamedTuple, Optional

import structlog
from fc.maintenance.estimate import Estimate


class RebootType(str, Enum):
    WARM = "reboot"
    COLD = "poweroff"


class ActivityMergeResult(NamedTuple):
    merged: Optional["Activity"] = None
    is_effective: bool = False
    is_significant: bool = False
    changes: dict = {}


class Activity:
    """Maintenance activity which is executed as request payload.

    Activities are executed possibly several times until they succeed or
    exceed their retry limit. Individual maintenance activities should
    subclass this class and add custom behaviour to its methods.

    Attributes: `stdout`, `stderr` capture the outcomes of shell-outs.
    `returncode` controls the resulting request state. If `duration` is
    set, it overrules execution timing done by the calling scope. Use
    this if a logical transaction spans several attempts, e.g. for
    reboots.
    """

    stdout: None | str = None
    stderr: None | str = None
    returncode: None | int = None
    duration: None | float = None
    request = None  # back-pointer, will be set in Request
    reboot_needed: None | RebootType = None
    # Do we predict that this activity will actually change anything?
    is_effective = True
    comment = ""
    estimate = Estimate("10m")
    log = None

    def __init__(self):
        """Creates activity object (add args if you like).

        Note that this method gets only called once and the value of
        __dict__ is serialized using PyYAML between runs.
        """
        pass

    def __getstate__(self):
        state = self.__dict__.copy()
        # Deserializing loggers breaks, remove them before serializing (to YAML).
        if "log" in state:
            del state["log"]
        if "request" in state:
            del state["request"]
        return state

    def set_up_logging(self, log):
        self.log = log.bind(activity_type=self.__class__.__name__)

    def run(self):
        """Executes maintenance activity.

        Execution takes place in a request-specific directory as CWD. Do
        whatever you want here, but do not destruct `request.yaml`.
        Directory contents is preserved between several attempts.

        This method is expected to update `self.stdout`, `self.stderr`, and
        `self.returncode` after each run. Request state is determined
        according to the EXIT_* constants in `state.py`. Any returncode
        not listed there means hard failure and causes the request to be
        archived. Uncaught exceptions are handled the same way.
        """
        self.returncode = 0

    def load(self):
        """Loads external state.

        This method gets called every time the Activity object is
        deserialized to perform additional state updating. This should
        be rarely needed, as the contents of self.__dict__ is preserved
        anyway. CWD is set to the request dir.
        """
        pass

    def dump(self):
        """Saves additional state during serialization."""
        pass

    def merge(self, other) -> ActivityMergeResult:
        """Merges in other activity. Settings from other have precedence.
        Returns merge result.
        """
        return ActivityMergeResult()

    def __rich__(self):
        cls = self.__class__
        out = f"{cls.__module__}.{cls.__qualname__}"
        match self.reboot_needed:
            case RebootType.WARM:
                out += " (warm reboot needed)"
            case RebootType.COLD:
                out += " (cold reboot needed)"

        return out
