import os
import traceback
from typing import NamedTuple

import fc.util.systemd_units
import structlog
from typer import Argument, Exit, Option, Typer


class Context(NamedTuple):
    verbose: bool


app = Typer(
    pretty_exceptions_show_locals=bool(
        os.getenv("FC_AGENT_SHOW_LOCALS", False)
    )
)
context: Context


@app.callback(no_args_is_help=True)
def fc_systemd(
    verbose: bool = Option(
        False,
        "--verbose",
        "-v",
        help="Show debug messages and code locations.",
    ),
):
    global context

    context = Context(
        verbose=verbose,
    )


@app.command()
def check_unit(
    unit_name: str = Argument(...),
):
    log = structlog.get_logger()
    try:
        result = fc.util.systemd_units.check_status(
            log,
            unit_name,
            critical_states=("failed", "inactive"),
            warning_states=tuple(),
        )
    except Exception:
        print("UNKNOWN: Exception occurred while running checks")
        traceback.print_exc()
        raise Exit(3)

    print(result.format_output())
    if result.exit_code:
        raise Exit(result.exit_code)


@app.command(help="")
def check_units(
    critical: bool = Option(
        False,
        help=(
            "Treat unexpected states as critical. By default, a warning is "
            "issued."
        ),
    ),
    exclude: list[str] = Option(
        [],
        help="Units excluded from the check. Can be specified more than once.",
    ),
):
    log = structlog.get_logger()
    try:
        result = fc.util.systemd_units.check_find_failed(
            log, exclude, critical
        )
    except Exception:
        print("UNKNOWN: Exception occurred while running checks")
        traceback.print_exc()
        raise Exit(3)

    print(result.format_output())
    if result.exit_code:
        raise Exit(result.exit_code)


if __name__ == "__main__":
    app()
