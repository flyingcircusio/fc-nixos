"""Shared test fixtures: structlog configuration isolation.

Tests that run a tool's ``main()`` reconfigure structlog globally with
``PrintLoggerFactory(file=sys.stderr)`` -- binding the logger to pytest's
per-test capture object. Once that test ends, the capture file is closed
and any LATER in-process log call dies with
``ValueError: I/O operation on closed file``. Resetting structlog after
every test keeps the global configuration test-local.
"""

from __future__ import annotations

import pytest
import structlog


@pytest.fixture(autouse=True)
def _structlog_isolated():
    yield
    structlog.reset_defaults()
