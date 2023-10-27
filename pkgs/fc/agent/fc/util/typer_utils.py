import os

import fc.util.logging
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
