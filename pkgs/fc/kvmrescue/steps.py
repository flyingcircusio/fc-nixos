"""Step registration and the runner.

The order of the rescue is the order the steps are defined in, and nowhere else:
a step's prerequisites are simply every step defined above it. The registry
therefore knows the sequence without executing anything, which is what lets an
interrupted rescue resume and `--list` tell the truth.

The runner calls every step from the same frame, so steps never call each other
and a traceback during an incident shows one step rather than a chain.
"""

from collections.abc import Callable, Iterator
from dataclasses import dataclass
from typing import Protocol, cast

from state import RescueState


class RescueDone(Exception):
    """Raised by a step to end the rescue early, but successfully.

    Carries the reason to show the operator, e.g. the dead host turning out to
    hold no locks at all, leaving nothing to rescue.
    """


class StepHost(Protocol):
    """The object whose methods are the steps.

    Only declares what the machinery touches; steps are reached by name via
    `getattr`. Keeps this module from importing the rescue script back.
    """

    state: RescueState


@dataclass(frozen=True)
class StepDef:
    name: str
    index: int
    doc: str  # first docstring line, for --list and progress output
    skip: bool  # may this step skip itself once recorded as done?


STEPS: list[StepDef] = []
STEPS_BY_NAME: dict[str, StepDef] = {}


def step(
    *, skip: bool = True
) -> Callable[[Callable[..., None]], Callable[..., None]]:
    """Register a step host's method as a rescue step, in definition order.

    `skip=False` marks a step that runs again on every pass even once recorded
    as done -- for safety gates that want re-confirming, and for steps that just
    re-print something out of the persisted state.
    """

    def register(fn: Callable[..., None]) -> Callable[..., None]:
        definition = StepDef(
            name=fn.__name__,
            index=len(STEPS),
            doc=(fn.__doc__ or "").strip().splitlines()[0],
            skip=skip,
        )
        STEPS.append(definition)
        STEPS_BY_NAME[definition.name] = definition
        return fn

    return register


@dataclass
class StepRun:
    """One step, handed to the caller to invoke.

    The runner yields these; the loop in `main` decides how to announce a step
    and then calls it. Invoking a skipped run is a no-op, so the reporting of
    skips lives in the same place as all the other output.
    """

    host: StepHost
    definition: StepDef
    skipped: bool
    called: bool = False

    def __call__(self) -> None:
        self.called = True
        if self.skipped:
            return
        stepmethod = cast(
            Callable[[], None], getattr(self.host, self.definition.name)
        )
        stepmethod()
        # Only reached when the body returned normally, so a step that raised
        # stays unrecorded and a later run picks it up again.
        self.host.state.mark_done(self.definition.name)


def run(
    host: StepHost, start: StepDef | None = None, skip: bool = True
) -> Iterator[StepRun]:
    for definition in STEPS[start.index if start else 0 :]:
        step_run = StepRun(
            host,
            definition,
            skipped=(
                skip
                and definition.skip
                and definition.name in host.state.completed
            ),
        )
        yield step_run
        if not step_run.called:
            # The runner hands a step out but does not run it, so a caller
            # that forgets to would otherwise walk the whole registry in
            # silence, doing nothing at all.
            raise RuntimeError(
                f"{definition.name} was yielded but never invoked"
            )


def missing_prerequisites(
    definition: StepDef, completed: list[str]
) -> list[StepDef]:
    return [
        earlier
        for earlier in STEPS[: definition.index]
        if earlier.name not in completed
    ]
