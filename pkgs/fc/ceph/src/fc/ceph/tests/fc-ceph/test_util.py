"""`run` and `run_async` must stay interchangeable: same command echo, same
output, same failure behaviour."""

import asyncio
from subprocess import CalledProcessError

import pytest

from fc.ceph.util import run, run_async

FAILING = ("-c", "echo out; echo err >&2; exit 3")


def test_success_returns_the_same_output_and_echo(capsys):
    assert run.echo("hello") == b"hello\n"
    expected = capsys.readouterr().out

    assert asyncio.run(run_async.echo("hello")) == b"hello\n"
    assert capsys.readouterr().out == expected == "$ echo hello\n"


def test_input_is_passed_the_same_way(capsys):
    assert run.cat(input=b"hello\n") == b"hello\n"
    expected = capsys.readouterr().out

    assert asyncio.run(run_async.cat(input=b"hello\n")) == b"hello\n"
    assert capsys.readouterr().out == expected


def test_encoding_decodes_the_same_way(capsys):
    assert run.echo("hello", encoding="ascii") == "hello\n"
    expected = capsys.readouterr().out

    assert asyncio.run(run_async.echo("hello", encoding="ascii")) == "hello\n"
    assert capsys.readouterr().out == expected


def test_failure_raises_the_same_way(capsys):
    with pytest.raises(CalledProcessError) as sync_error:
        run.sh(*FAILING)
    expected = capsys.readouterr().out

    with pytest.raises(CalledProcessError) as async_error:
        asyncio.run(run_async.sh(*FAILING))
    assert capsys.readouterr().out == expected

    assert sync_error.value.returncode == async_error.value.returncode == 3
    assert sync_error.value.stdout == async_error.value.stdout == b"out\n"
    assert sync_error.value.stderr == async_error.value.stderr == b"err\n"


def test_check_false_stays_quiet_the_same_way(capsys):
    run.sh(*FAILING, check=False)
    expected = capsys.readouterr().out

    asyncio.run(run_async.sh(*FAILING, check=False))
    assert capsys.readouterr().out == expected


def test_aliases_are_the_same(capsys):
    with pytest.raises(FileNotFoundError):
        run.radosgw_admin("--help")
    expected = capsys.readouterr().out

    with pytest.raises(FileNotFoundError):
        asyncio.run(run_async.radosgw_admin("--help"))
    assert capsys.readouterr().out == expected == "$ radosgw-admin --help\n"
