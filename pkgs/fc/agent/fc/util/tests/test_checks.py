import textwrap

from fc.util.checks import CheckResult


def test_check_result_ok():
    check_result = CheckResult(ok_info=["Everything is as expected."])
    out = check_result.format_output()
    expected = "OK: Everything is as expected."
    assert out == expected
    assert check_result.exit_code == 0


def test_check_result_ok_multi():
    check_result = CheckResult(
        ok_info=["Everything is as expected.", "Also additional info: 5, 3, 7."]
    )
    out = check_result.format_output()
    expected = textwrap.dedent(
        """
        OK: Everything is as expected.
        Also additional info: 5, 3, 7.
        """
    ).strip()

    assert out == expected


def test_check_result_warnings():
    check_result = CheckResult(
        warnings=["First warning.", "Second warning."],
        ok_info=["Everything is as expected."],
    )
    out = check_result.format_output()
    expected = textwrap.dedent(
        """
        WARNING: First warning.
        Second warning.
        """
    ).strip()

    assert out == expected
    assert check_result.exit_code == 1


def test_check_result_everything():
    check_result = CheckResult(
        errors=["First error.", "Second error."],
        warnings=["First warning.", "Second warning."],
        ok_info=["Everything is as expected."],
    )
    out = check_result.format_output()
    expected = textwrap.dedent(
        """
        CRITICAL: First error.
        Second error.
        First warning.
        Second warning.
        """
    ).strip()

    assert check_result.exit_code == 2

    assert out == expected
