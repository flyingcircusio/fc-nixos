from ..cluster import Cluster, CephCmdError
import pytest
import pkg_resources
import mock


@pytest.fixture
def cluster():
    return Cluster(pkg_resources.resource_filename(
        __name__, 'fixtures/ceph.conf'))


class TestCluster(object):

    def test_default_pool_size(self, cluster):
        assert (2, 1) == cluster.default_pool_size()

    def test_generic_ceph_cmd_should_obey_dry_run(self, cluster, capsys):
        cluster.dry_run = True
        cluster.generic_ceph_cmd(['ceph'], ['subcommand'])
        out, err = capsys.readouterr()
        assert err == "*** dry-run: ['ceph', 'subcommand']\n"

    @mock.patch('subprocess.Popen')
    def test_generic_ceph_cmd_returns_stdout(self, popen, cluster):
        p = popen.return_value
        p.communicate.return_value = ('out', 'err')
        p.returncode = 0
        assert ('out', 'err') == cluster.generic_ceph_cmd(
            ['ceph'], ['subcommand'])

    @mock.patch('subprocess.Popen')
    def test_generic_ceph_cmd_raises_on_failure(self, popen, cluster):
        p = popen.return_value
        p.communicate.return_value = ('', '')
        p.returncode = 1
        with pytest.raises(CephCmdError):
            cluster.generic_ceph_cmd(['ceph'], ['subcommand'])

    @mock.patch('subprocess.Popen')
    def test_generic_ceph_cmd_accepts_failure(self, popen, cluster):
        p = popen.return_value
        p.communicate.return_value = ('', '')
        p.returncode = 2
        assert ('', '', 2) == cluster.generic_ceph_cmd(
            ['ceph'], ['subcommand'], accept_failure=True)

    def test_default_pg_num(self, cluster):
        assert 32 == cluster.default_pg_num()

    def test_rbd_obeys_ceph_parameters(self):
        cluster = Cluster('/path/to/ceph.conf')
        setattr(cluster, 'generic_ceph_cmd',
                lambda a, *args: a)
        cluster.ceph_id = 'host1'
        assert (['rbd', '--id', 'host1', '-c', '/path/to/ceph.conf'] ==
                cluster.rbd(['ls']))
