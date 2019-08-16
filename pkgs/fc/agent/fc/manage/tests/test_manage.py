from requests import HTTPError
from pytest import raises, fixture
import responses
from responses import HEAD
from fc.manage.manage import Channel


@fixture
def mocked_responses():
    with responses.RequestsMock() as rsps:
        yield rsps


def expr_url(url):
    return url + 'nixexprs.tar.xz'


def test_channel_eq():
    ch1 = Channel('file://1')
    ch2 = Channel('file://2')
    assert ch1 == ch1
    assert ch1 != ch2


def test_channel_from_expr_url(mocked_responses):
    url = 'https://hydra.flyingcircus.io/build/54522/download/1/nixexprs.tar.xz'
    mocked_responses.add(responses.HEAD, url)
    ch = Channel(url)
    assert ch.resolved_url == url


def test_channel_from_url_with_redirect(mocked_responses):
    url = 'https://hydra.flyingcircus.io/channel/custom/flyingcircus/fc-19.03-staging/release/'
    final_url = 'https://hydra.flyingcircus.io/build/54715/download/1/nixexprs.tar.xz'

    mocked_responses.add(
        responses.HEAD, expr_url(url), status=302, headers={'Location': final_url}
    )
    mocked_responses.add(responses.HEAD, final_url)
    ch = Channel(url)
    assert ch.resolved_url == final_url


def test_channel_wrong_url_should_raise(mocked_responses):
    url = 'https://nothing.here/'
    mocked_responses.add(responses.HEAD, expr_url(url), status=404)

    with raises(HTTPError):
        Channel(url)
