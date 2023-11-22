import os
from functools import wraps

import fc.util.logging
import rich
import structlog
import typer


class FCTyperApp(typer.Typer):
    def __init__(self, command_name):
        # Showing local variables may leak secrets, don't do it in production!
        super().__init__(pretty_exceptions_show_locals=False)
        self.command_name = command_name

    def __call__(self):
        try:
            super().__call__()
        except Exception as e:
            if fc.util.logging.logging_initialized():
                try:
                    log = structlog.get_logger()
                    log.error(
                        "unhandled-exception",
                        exc_info=True,
                        command=self.command_name,
                        _log_settings=dict(console_ignore=True),
                    )
                except:
                    # Raise the original exception when logging fails.
                    print("WARNING: logging an unhandled exception failed.")
                    raise e
            else:
                # Raise the original exception when our logging is not
                # initialized.
                print(
                    "WARNING: could not log an unhandled exception because "
                    "structured logging has not been initialized."
                )
                raise e

            # Always raise the original exception if we are not running in a
            # systemd unit. The exception hook installed by typer will take
            # care of it and pretty-print the exception for interactive use.
            if not os.environ.get("INVOCATION_ID"):
                raise e


def requires_sudo(func):
    @wraps(func)
    def root_maybe_sudo(*args, **kwargs):
        if os.getuid() != 0:
            rich.print(
                "[bold red]Error:[/bold red] This command needs root "
                "permissions. You might be able to run it with `sudo`."
            )
            raise typer.Exit(77)

        return func(*args, **kwargs)

    return root_maybe_sudo


def requires_root(func):
    @wraps(func)
    def root_only(*args, **kwargs):
        if os.getuid() != 0:
            rich.print(
                "[bold red]Error:[/bold red] Only root can use this command."
            )
            raise typer.Exit(77)

        return func(*args, **kwargs)

    return root_only
