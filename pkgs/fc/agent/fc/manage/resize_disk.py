"""Resize filesystems.

We expect the root partition to be partition 1 on its device, but we're
looking up the device by checking the root partition by label first.
"""

from pathlib import Path

import fc.util.disk
import structlog
import typer
from fc.util.logging import init_logging
from typer import Option

log = structlog.get_logger()
app = typer.Typer()


@app.command()
def resize_disk(
    verbose: bool = False,
    logdir: Path = Option(
        exists=True, file_okay=False, writable=True, default="/var/log"
    ),
):
    init_logging(verbose, logdir)
    log.info("resize-disk-start")
    try:
        fc.util.disk.resize()
    except Exception:
        log.error("resize-disk-exception", exc_info=True)
        raise typer.Exit(1)

    log.info("resize-disk-finished")
