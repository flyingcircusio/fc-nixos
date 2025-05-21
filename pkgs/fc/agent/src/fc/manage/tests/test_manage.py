from unittest.mock import MagicMock, Mock

import fc.manage.manage
import responses
from fc.manage.manage import Channel
from pytest import fixture, raises
from requests import HTTPError


def expr_url(url):
    return url + "nixexprs.tar.xz"


def test_channel_eq(logger):
    ch1 = Channel(logger, "file://1")
    ch2 = Channel(logger, "file://2")
    assert ch1 == ch1
    assert ch1 != ch2


def test_channel_str_local_checkout(logger):
    channel = Channel(logger, "file://1", name="name", environment="env")
    assert (
        str(channel) == "<Channel name=name, version=local-checkout, from=1>"
    )


def test_channel_str(logger, mocked_responses):
    url = (
        "https://hydra.flyingcircus.io/build/54522/download/1/nixexprs.tar.xz"
    )
    mocked_responses.add(responses.HEAD, url)
    channel = Channel(logger, url, name="name", environment="env")
    assert str(channel) == f"<Channel name=name, version=unknown, from={url}>"


def test_channel_from_expr_url(logger, mocked_responses):
    url = (
        "https://hydra.flyingcircus.io/build/54522/download/1/nixexprs.tar.xz"
    )
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
