import contextlib
import textwrap
import uuid
from pathlib import Path

import shortuuid
import structlog
from fc.maintenance.activity import Activity
from fc.maintenance.reqmanager import ReqManager
from fc.maintenance.request import Request
from pytest import fixture


@fixture
def agent_maintenance_config(tmpdir):
    config_file = str(tmpdir / "fc-agent.conf")
    with open(config_file, "w") as f:
        f.write(
            textwrap.dedent(
                """\
            [maintenance-enter]
            demo = echo "entering demo"

            [maintenance-leave]
            demo = echo "leaving demo"
            dummy =
            """
            )
        )
    return config_file


@fixture
def reqmanager(tmpdir, agent_maintenance_config):
    with ReqManager(
        Path(tmpdir), config_file=Path(agent_maintenance_config)
    ) as rm:
        yield rm


@fixture
def request_population(tmpdir, agent_maintenance_config):
    @contextlib.contextmanager
    def _request_population(n):
        """Creates a ReqManager with a pregenerated population of N requests.

        The ReqManager and a list of Requests are passed to the calling code.
        """
        with ReqManager(
            Path(tmpdir), config_file=Path(agent_maintenance_config)
        ) as reqmanager:
            requests = []
            for i in range(n):
                req = Request(Activity(), 60, comment=str(i))
                req._reqid = shortuuid.encode(uuid.UUID(int=i))
                reqmanager.add(req)
                requests.append(req)
            yield (reqmanager, requests)

    return _request_population


@fixture
def logger():
    _logger = structlog.get_logger()
    _logger.trace = lambda *a, **k: None
    return _logger
