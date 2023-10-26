import contextlib
import shutil
import textwrap
import unittest
import uuid
from pathlib import Path

import responses
import shortuuid
import structlog
from fc.maintenance.activity import Activity
from fc.maintenance.reqmanager import ReqManager
from fc.maintenance.request import Request
from pytest import fixture


@fixture
def agent_maintenance_config(tmp_path):
    config_file = str(tmp_path / "fc-agent.conf")
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
def reqmanager(tmp_path, logger, agent_maintenance_config):
    spooldir = tmp_path / "maintenance"
    spooldir.mkdir()
    enc_path = tmp_path / "enc.json"
    enc_path.write_text("{}")
    with unittest.mock.patch("fc.util.directory.connect"):
        with ReqManager(
            spooldir=spooldir,
            enc_path=enc_path,
            config_file=agent_maintenance_config,
            log=logger,
        ) as rm:
            yield rm


@fixture
def request_population(tmp_path, agent_maintenance_config, reqmanager):
    @contextlib.contextmanager
    def _request_population(n):
        """Creates a ReqManager with a pregenerated population of N requests.

        The ReqManager and a list of Requests are passed to the calling code.
        """
        with reqmanager:
            requests = []
            for i in range(n):
                req = Request(Activity(), comment=str(i))
                req._reqid = shortuuid.encode(uuid.UUID(int=i))
                reqmanager.add(req)
                requests.append(req)
            yield (reqmanager, requests)

    return _request_population


@fixture
def logger():
    # pytest-structlog patches away structlog.config, but we can still use
    # structlog._config.configure...
    # We need to do that to support our custom `trace` logging method.
    # It fails with BoundLoggingFilteringAtNotset which is the default wrapper.
    structlog._config.configure(wrapper_class=structlog.BoundLogger)
    return structlog.get_logger()


@fixture
def mocked_responses():
    with responses.RequestsMock() as rsps:
        yield rsps
