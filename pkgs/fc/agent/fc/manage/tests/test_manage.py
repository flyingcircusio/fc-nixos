import textwrap
from unittest.mock import MagicMock, Mock

import responses
import structlog
from fc.manage.manage import Channel
from pytest import fixture, raises
from requests import HTTPError


@fixture
def mocked_responses():
    with responses.RequestsMock() as rsps:
        yield rsps


@fixture
def logger():
    return structlog.get_logger()


def expr_url(url):
    return url + "nixexprs.tar.xz"


def test_channel_eq(logger):
    ch1 = Channel(logger, "file://1")
    ch2 = Channel(logger, "file://2")
    assert ch1 == ch1
    assert ch1 != ch2


def test_channel_str_local_checkout(logger):
    channel = Channel(logger, "file://1", name="name", environment="env")
    assert str(channel) == "<Channel name=name, version=local-checkout, from=1>"


def test_channel_str(logger, mocked_responses):
    url = "https://hydra.flyingcircus.io/build/54522/download/1/nixexprs.tar.xz"
    mocked_responses.add(responses.HEAD, url)
    channel = Channel(logger, url, name="name", environment="env")
    assert str(channel) == f"<Channel name=name, version=unknown, from={url}>"


def test_channel_from_expr_url(logger, mocked_responses):
    url = "https://hydra.flyingcircus.io/build/54522/download/1/nixexprs.tar.xz"
    mocked_responses.add(responses.HEAD, url)
    ch = Channel(logger, url)
    assert ch.resolved_url == url


def test_channel_from_url_with_redirect(logger, mocked_responses):
    url = "https://hydra.flyingcircus.io/channel/custom/flyingcircus/fc-19.03-staging/release/"
    final_url = (
        "https://hydra.flyingcircus.io/build/54715/download/1/nixexprs.tar.xz"
    )

    mocked_responses.add(
        responses.HEAD,
        expr_url(url),
        status=302,
        headers={"Location": final_url},
    )
    mocked_responses.add(responses.HEAD, final_url)
    ch = Channel(logger, url)
    assert ch.resolved_url == final_url


def test_channel_wrong_url_should_raise(logger, mocked_responses):
    url = "https://nothing.here/"
    mocked_responses.add(responses.HEAD, expr_url(url), status=404)

    with raises(HTTPError):
        Channel(logger, url)


def test_channel_prepare_maintenance(
    log, mocked_responses, logger, monkeypatch, tmp_path
):
    channel_url = (
        "https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz"
    )
    version = "21.05.1367.817a5b0"
    environment = "fc-21.05-dev"
    system_path = f"/nix/store/v49jzgwblcn9vkrmpz92kzw5pkbsn0vz-nixos-system-test-{version}"
    changes = {
        "reload": ["nginx.service"],
        "restart": ["telegraf.service"],
        "start": ["postgresql.service"],
        "stop": ["postgresql.service"],
    }

    expected_request_comment = textwrap.dedent(
        f"""\
        System update to {version}
        Environment: {environment}
        Channel URL: {channel_url}
        Stop: postgresql
        Restart: telegraf
        Start: postgresql
        Reload: nginx
        Will schedule a reboot to activate the changed kernel.
    """
    )

    mocked_responses.add(responses.HEAD, channel_url)
    monkeypatch.setattr("fc.manage.manage.NEXT_SYSTEM", tmp_path)
    build_system_mock = Mock(return_value=system_path)
    monkeypatch.setattr("fc.util.nixos.build_system", build_system_mock)
    dry_activate_system_mock = Mock(return_value=changes)
    monkeypatch.setattr(
        "fc.util.nixos.dry_activate_system", dry_activate_system_mock
    )

    def fake_changed_kernel_version(path):
        if path == "/run/current-system/kernel":
            return "5.10.45"
        elif path == "/run/next-system/result/kernel":
            return "5.10.50"

    monkeypatch.setattr(
        "fc.util.nixos.kernel_version", fake_changed_kernel_version
    )

    req_manager_mock = MagicMock()
    req_manager_mock.return_value.__enter__.return_value.add = (
        rm_add_mock
    ) = Mock()
    monkeypatch.setattr("fc.maintenance.ReqManager", req_manager_mock)

    channel = Channel(logger, channel_url, environment=environment)
    channel.version = lambda: version

    channel.prepare_maintenance()

    build_system_mock.assert_called_once_with(
        "/root/.nix-defexpr/channels/next",
        out_link=tmp_path / "result",
        log=channel.log,
    )
    dry_activate_system_mock.assert_called_once_with(system_path, channel.log)
    assert log.has("channel-prepare-maintenance-start")
    # Check maintenance request.
    rm_add_mock.assert_called_once()
    req = rm_add_mock.call_args[0][0]
    assert req.comment == expected_request_comment
    assert channel_url in req.activity.script
