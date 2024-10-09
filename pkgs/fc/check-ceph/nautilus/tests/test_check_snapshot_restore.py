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


def test_exitcodes():
    assert snapcheck.SensuStatus.OK == 0
    assert snapcheck.SensuStatus.WARN == 1
    assert snapcheck.SensuStatus.CRITICAL == 2
    assert snapcheck.SensuStatus.UNKNOWN == 3


def test_statuscodes_critical_is_highest():
    crit = snapcheck.SensuStatus.CRITICAL
    for status in snapcheck.SensuStatus:
        assert crit.merge(status) == crit


def test_statuscodes_warn():
    warn = snapcheck.SensuStatus.WARN
    higher_prio = [snapcheck.SensuStatus.CRITICAL]
    lower_prio = [
        snapcheck.SensuStatus.WARN,
        snapcheck.SensuStatus.UNKNOWN,
        snapcheck.SensuStatus.OK,
    ]

    for status in higher_prio:
        assert warn.merge(status) == status

    for status in lower_prio:
        assert warn.merge(status) == warn


def test_statuscodes_unknown():
    unknown = snapcheck.SensuStatus.UNKNOWN
    higher_prio = [
        snapcheck.SensuStatus.CRITICAL,
        snapcheck.SensuStatus.WARN,
    ]
    lower_prio = [
        snapcheck.SensuStatus.UNKNOWN,
        snapcheck.SensuStatus.OK,
    ]

    for status in higher_prio:
        assert unknown.merge(status) == status

    for status in lower_prio:
        assert unknown.merge(status) == unknown


def test_statuscodes_ok():
    ok = snapcheck.SensuStatus.OK
    higher_prio = [
        snapcheck.SensuStatus.CRITICAL,
        snapcheck.SensuStatus.WARN,
        snapcheck.SensuStatus.UNKNOWN,
    ]
    lower_prio = [
        snapcheck.SensuStatus.OK,
    ]

    for status in higher_prio:
        assert ok.merge(status) == status

    for status in lower_prio:
        assert ok.merge(status) == ok


def test_snapshot_fits(snap_ok):
    assert snap_ok.restore_impact[0] == snapcheck.SensuStatus.OK


def test_snapshot_warn(snap_warn):
    assert snap_warn.restore_impact[0] == snapcheck.SensuStatus.WARN


def test_snapshot_critical(snap_critical):
    assert snap_critical.restore_impact[0] == snapcheck.SensuStatus.CRITICAL

    snap_critical.size = 10000000  # larger than total pool

    assert snap_critical.restore_impact[0] == snapcheck.SensuStatus.CRITICAL


def test_snapshot_oddities(snapshot):
    snapshot.pool.root.size = 1000000
    snapshot.pool.root.usage = 0
    snapshot.size = 0

    assert snapshot.restore_impact[0] == snapcheck.SensuStatus.OK

    # check that passed thresholds are used
    snapshot.pool.root.thresholds = snapcheck.Thresholds(1.0, 1.0)
    snapshot.size = snapshot.pool.root.size - 1
    assert snapshot.restore_impact[0] == snapcheck.SensuStatus.OK


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
    assert ex.value.code == snapcheck.SensuStatus.CRITICAL.value

    with pytest.raises(SystemExit) as ex:
        snapcheck.parse_config(["progname", "multitrack", "drifting"])
    assert ex.value.code == snapcheck.SensuStatus.CRITICAL.value


def test_parse_config_file_problems(tmp_path):
    # TODO: possibly match output for particular error messages
    with pytest.raises(SystemExit) as ex:
        snapcheck.parse_config(["progname", tmp_path / "nonexisting.toml"])
    assert ex.value.code == snapcheck.SensuStatus.CRITICAL.value

    # permission issues
    shutil.copy("./tests/config.toml", tmp_path / "permission.toml")
    os.chmod(tmp_path / "permission.toml", 0)
    with pytest.raises(SystemExit) as ex:
        snapcheck.parse_config(["progname", tmp_path / "permission.toml"])
    assert ex.value.code == snapcheck.SensuStatus.CRITICAL.value

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
    assert ex.value.code == snapcheck.SensuStatus.CRITICAL.value

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
    assert ex.value.code == snapcheck.SensuStatus.CRITICAL.value


def test_raw_cluster_stats_parsing(raw_cluster_stats_conn):
    result = list(snapcheck._ceph_osd_df_tree_roots(raw_cluster_stats_conn))

    assert len(result) == 2


def test_parse_pools(
    parsed_raw_cluster_fillstats, example_thresholds, default_pool_roots
):
    (parse_status, parsed_pools) = snapcheck.parse_pools(
        parsed_raw_cluster_fillstats, default_pool_roots, example_thresholds
    )

    assert len(parsed_pools) == 2
    assert parse_status == snapcheck.SensuStatus.OK
    # check for KiB -> B conversion
    assert parsed_pools[0].root.size == 109951162777600
    assert parsed_pools[1].root.used == 65970697666560


def test_parse_pools_no_stats_available(example_thresholds, default_pool_roots):
    (parse_status, parsed_pools) = snapcheck.parse_pools(
        iter([]), default_pool_roots, example_thresholds
    )

    assert parse_status == snapcheck.SensuStatus.UNKNOWN
    assert not parsed_pools


def test_parse_pools_drop_non_relevant_pools(
    parsed_raw_cluster_fillstats, default_pool_roots, example_thresholds
):
    default_pool_roots["ssd"] = []
    (parse_status, parsed_pools) = snapcheck.parse_pools(
        parsed_raw_cluster_fillstats, default_pool_roots, example_thresholds
    )

    assert len(parsed_pools) == 1
    assert parsed_pools[0].name == "rbd.hdd"
    assert parse_status == snapcheck.SensuStatus.OK


def test_query_snaps(poolio_connection_mock):
    rbd_ssd = snapcheck.Pool("rbd.ssd", None)
    rbd_hdd = snapcheck.Pool("rbd.hdd", None)
    snaps = snapcheck.query_snaps(poolio_connection_mock, [rbd_ssd, rbd_hdd])

    assert len(snaps) == 3

    snap_pools = set()
    # snaps are collected from both pools
    for found_snap in snaps:
        snap_pools.add(found_snap.pool.name)

    assert rbd_ssd.name in snap_pools
    assert rbd_hdd.name in snap_pools

    firstsnap = snaps[0]
    assert firstsnap.image == "test03"
    assert firstsnap.snapname == "footest"
    assert firstsnap.size == 1024


def test_query_snaps_nopools(poolio_connection_mock):
    snaps = snapcheck.query_snaps(poolio_connection_mock, [])

    assert not snaps


def test_query_snaps_empty_cluster(poolio_connection_mock):
    # situation after bootstrapping: no rbd images, no snapshots
    snaps = snapcheck.query_snaps(
        poolio_connection_mock, [snapcheck.Pool("emptypool", None)]
    )

    assert not snaps


def test_categorise_snaps(snap_ok, snap_warn, snap_critical):
    categorised = snapcheck.categorise_snaps(
        [snap_ok, snap_warn, snap_critical]
    )
    assert len(categorised.keys()) == 2
    assert categorised[snapcheck.SensuStatus.CRITICAL] == [snap_critical]
    assert categorised[snapcheck.SensuStatus.WARN] == [snap_warn]


def test_categorise_snaps_nosnaps():
    categorised = snapcheck.categorise_snaps([])
    for category in categorised.values():
        for snap in category:
            pytest.fail("there should be no snapshot")


def test_eval_report(snap_warn, snap_critical):
    categorised = {
        snapcheck.SensuStatus.WARN: [snap_warn],
        snapcheck.SensuStatus.CRITICAL: [snap_critical],
    }

    overall_status, report = snapcheck.eval_report(categorised)
    assert overall_status == snapcheck.SensuStatus.CRITICAL
    assert "Total status: CRITICAL" in report
    assert snap_warn.snapname in report
    assert "Restoring the snapshot rbd.hdd/test01@backy-1337" in report
    assert "1 CRITICAL snapshot(s)" in report
    assert "1 WARN snapshot(s)" in report


def test_eval_report_only_one_category(snap_warn):
    categorised = {
        snapcheck.SensuStatus.WARN: [snap_warn],
        snapcheck.SensuStatus.CRITICAL: [],
    }

    overall_status, report = snapcheck.eval_report(categorised)
    assert overall_status == snapcheck.SensuStatus.WARN

    assert "CRITICAL" not in report


def test_eval_report_all_okay():
    overall_status, report = snapcheck.eval_report({})

    assert overall_status == snapcheck.SensuStatus.OK
    assert "Total status: OK" in report
