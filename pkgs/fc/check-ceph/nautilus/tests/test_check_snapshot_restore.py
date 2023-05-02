import json
import os
import shutil
from collections import namedtuple
from copy import deepcopy
from textwrap import dedent
from unittest import mock

import fc.check_ceph.check_snapshot_restore as snapcheck
import pytest

# fixtures and mocks are in conftest.py


def test_fill_warnings(cluster_stats, snap_data, default_pool_roots):
    thresholds = snapcheck.Thresholds(nearfull=0.85, full=0.95)
    # retrieve and create mock data
    largest_snaps = {
        rootname: ("nopoolname", snap_data) for rootname in default_pool_roots
    }
    roots = list(default_pool_roots.keys())
    # normal case: exit code 0
    assert 0 == snapcheck.eval_fill_warnings(
        cluster_stats, largest_snaps, thresholds
    )

    # situation after bootstrapping: no rbd images, no snapshots
    assert 0 == snapcheck.eval_fill_warnings(cluster_stats, {}, thresholds)

    # warn level: craft image size such that it exceeds
    warn_level_snap = deepcopy(snap_data)
    warn_level_snap["size_bytes"] = 25 * 1024**4 + 10
    critical_level_snap = deepcopy(snap_data)
    critical_level_snap["size_bytes"] = 35 * 1024**4 + 10

    assert 1 == snapcheck.eval_fill_warnings(
        cluster_stats,
        {
            roots[0]: ("nopoolname", snap_data),
            roots[1]: ("nopoolname", warn_level_snap),
        },
        thresholds,
    )
    assert 1 == snapcheck.eval_fill_warnings(
        cluster_stats,
        {
            roots[0]: ("nopoolname", warn_level_snap),
            roots[1]: ("nopoolname", snap_data),
        },
        thresholds,
    )
    assert 2 == snapcheck.eval_fill_warnings(
        cluster_stats,
        {
            roots[0]: ("nopoolname", snap_data),
            roots[1]: ("nopoolname", critical_level_snap),
        },
        thresholds,
    )
    assert 2 == snapcheck.eval_fill_warnings(
        cluster_stats,
        {
            roots[0]: ("nopoolname", critical_level_snap),
            roots[1]: ("nopoolname", warn_level_snap),
        },
        thresholds,
    )

    # check that passed thresholds are used
    assert 0 == snapcheck.eval_fill_warnings(
        cluster_stats,
        {roots[0]: ("nopoolname", critical_level_snap)},
        snapcheck.Thresholds(1.0, 1.0),
    )

    below_warn_level_snap = warn_level_snap
    below_warn_level_snap["size_bytes"] -= 20
    assert 0 == snapcheck.eval_fill_warnings(
        cluster_stats,
        {roots[0]: ("nopoolname", below_warn_level_snap)},
        thresholds,
    )

    # unknown state: if desired cluster stats are not available
    broken_cluster_stats = deepcopy(cluster_stats)
    del broken_cluster_stats["default"]
    del broken_cluster_stats["ssd"]["kb_used"]
    assert 3 == snapcheck.eval_fill_warnings(
        broken_cluster_stats, largest_snaps, thresholds
    )


def test_cluster_fillstats(default_pool_roots, cluster_stats):
    """tests whether a (mocked) ceph osd df tree JSON output is parsed correctly
    to a dict containing only the desired crush roots.
    """

    conn_mock = mock.Mock()
    mock_data = {
        "some": "other data",
    }
    mock_data["nodes"] = [root for root in cluster_stats.values()]
    # add another root with a non-desired name
    non_desired_root = deepcopy(mock_data["nodes"][0])
    non_desired_root["name"] = "another_name"
    mock_data["nodes"].append(non_desired_root)

    conn_mock.mon_command = mock.Mock(return_value=(0, json.dumps(mock_data)))

    print(conn_mock.mon_command())
    assert (
        snapcheck.get_cluster_fillstats(conn_mock, default_pool_roots)
        == cluster_stats
    )

    # verify that non-root node types are dropped
    mock_data["nodes"][0]["type"] = "host"
    conn_mock.mon_command = mock.Mock(return_value=(0, json.dumps(mock_data)))
    assert (
        len(snapcheck.get_cluster_fillstats(conn_mock, default_pool_roots)) == 1
    )


def test_largest_snap_selection(rbd_image_mock):
    # relies on default mock data
    poolio = rbd_image_mock

    assert snapcheck.largest_snap_per_pool(poolio, "rbd.hdd") == {
        "imgname": "test01",
        "size_bytes": 2345678,
        "snapname": "backy-2342",
    }


# TODO: tests for get_largest_snaps over multiple pools of same root, but that needs to
# extend the mocking to the rados connection itself


def test_parse_config():
    (thresholds, pool_roots) = snapcheck.parse_config(
        ["progname", "./tests/config.toml"]
    )
    assert thresholds.nearfull == 0.85
    assert thresholds.full == 0.95
    assert pool_roots == {"default": ["rbd.hdd"], "ssd": ["rbd.ssd"]}


def test_parse_config_no_file():

    with pytest.raises(SystemExit) as ex:
        snapcheck.parse_config(["progname"])
    assert ex.value.code == snapcheck.EXIT_CRITICAL

    with pytest.raises(SystemExit) as ex:
        snapcheck.parse_config(["progname", "multitrack", "drifting"])
    assert ex.value.code == snapcheck.EXIT_CRITICAL


def test_parse_config_file_problems(tmp_path):
    # TODO: possibly match output for particular error messages
    with pytest.raises(SystemExit) as ex:
        snapcheck.parse_config(["progname", tmp_path / "nonexisting.toml"])
    assert ex.value.code == snapcheck.EXIT_CRITICAL

    # permission issues
    shutil.copy("./tests/config.toml", tmp_path / "permission.toml")
    os.chmod(tmp_path / "permission.toml", 0)
    with pytest.raises(SystemExit) as ex:
        snapcheck.parse_config(["progname", tmp_path / "permission.toml"])
    assert ex.value.code == snapcheck.EXIT_CRITICAL

    # broken toml file
    with open(tmp_path / "broken.toml", "wt") as brokentoml:
        print(
            dedent(
                """\
            [broken
            header]
            foo = "bar"
            """
            ),
            file=brokentoml,
        )
    with pytest.raises(SystemExit) as ex:
        snapcheck.parse_config(["progname", tmp_path / "broken.toml"])
    assert ex.value.code == snapcheck.EXIT_CRITICAL

    # wrong or missing values
    # yes, this could be done with a TextIO as well, but I'm using tmp_path already anyways
    with open(tmp_path / "missing.toml", "wt") as missingtoml:
        print(
            dedent(
                """\
            [thresholds]
            full = 0.95
            """
            ),
            file=missingtoml,
        )
    with pytest.raises(SystemExit) as ex:
        snapcheck.parse_config(["progname", tmp_path / "missing.toml"])
    assert ex.value.code == snapcheck.EXIT_CRITICAL
