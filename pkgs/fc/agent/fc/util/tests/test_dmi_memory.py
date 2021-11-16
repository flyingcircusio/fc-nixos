""" Unit-test for dmidecode parser"""

from fc.util.dmi_memory import calc_mem, get_device, main
import pkg_resources
from unittest import mock


def test_calc_mem():
    modules = [{
        'Size': '0MB'
    }, {
        'Size': '512MB'
    }, {
        'Size': '2048    MB'
    }, {
        'Size': '    9096 mb'
    }]
    res = calc_mem(modules)
    assert res == 11656


def test_get_device():
    entry = [
        'Memory Device', 'Total Width: Unknown', 'Type: Ram',
        'Locator: DIMM: 0'
    ]
    res = get_device(entry)
    assert res == {'Total Width': ' Unknown', 'Type': ' Ram'}


@mock.patch('subprocess.check_output')
def test_multibank_should_be_calculated_correctly(check_output):
    check_output().decode.return_value = pkg_resources.resource_string(
        __name__, 'dmidecode_multibank.out').decode('us-ascii')
    assert 24576 == main()


@mock.patch('subprocess.check_output')
def test_singlebank_should_be_calculated_correctly(check_output):
    check_output().decode.return_value = pkg_resources.resource_string(
        __name__, 'dmidecode.out').decode('us-ascii')
    assert 2048 == main()
