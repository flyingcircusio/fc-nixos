from fc.manage.resize import kernel_version
import pytest


@pytest.fixture
def dirsetup(tmpdir):
    drv = tmpdir.mkdir('abcdef-linux-4.4.27')
    current = tmpdir.mkdir('current')
    bzImage = drv.ensure('bzImage')
    (current / 'kernel').mksymlinkto(bzImage)
    mod = drv.mkdir('lib').mkdir('modules')
    return current / 'kernel', mod


def test_kernel_versions_equal(dirsetup, tmpdir):
    kernel, mod = dirsetup
    mod.mkdir('4.4.27')
    assert '4.4.27' == kernel_version(str(kernel))


def test_kernel_version_empty(dirsetup, tmpdir):
    kernel, mod = dirsetup
    with pytest.raises(RuntimeError):
        kernel_version(str(kernel))


def test_multiple_kernel_versions(dirsetup, tmpdir):
    kernel, mod = dirsetup
    mod.mkdir('4.4.27')
    mod.mkdir('4.4.28')
    with pytest.raises(RuntimeError):
        kernel_version(str(kernel))
