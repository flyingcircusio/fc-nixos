""" Unit-test for dmidecode parser"""

from unittest import mock

import pkg_resources
from fc.util.dmi_memory import calc_mem, get_device, main


def test_calc_mem():
    modules = [
        {"Size": "0GB"},
        {"Size": "1GB"},
        {"Size": "1    GB"},
        {"Size": "    9 gb"},
    ]
    res = calc_mem(modules)
    assert res == 11264


def test_get_device():
    entry = [
        "Memory Device",
        "Total Width: Unknown",
        "Type: Ram",
        "Locator: DIMM: 0",
    ]
    res = get_device(entry)
    assert res == {"Total Width": " Unknown", "Type": " Ram"}


@mock.patch("subprocess.check_output")
def test_multibank_should_be_calculated_correctly(check_output):
    check_output().decode.return_value = pkg_resources.resource_string(
        __name__, "dmidecode_multibank.out"
    ).decode("us-ascii")
    assert 262144 == main()


@mock.patch("subprocess.check_output")
def test_singlebank_should_be_calculated_correctly(check_output):
    check_output().decode.return_value = pkg_resources.resource_string(
        __name__, "dmidecode.out"
    ).decode("us-ascii")
    assert 8192 == main()
