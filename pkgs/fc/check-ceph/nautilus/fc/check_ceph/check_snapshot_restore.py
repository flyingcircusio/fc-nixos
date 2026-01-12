"""Check that the largest RBD image snapshot of each Ceph cluster root can be restored,
without exceeding the near_full threshold of the cluster capacity.
Please consider that this is not a guarantee for not getting `OSD_NEARFULL` warnings,
as individual fill levels of OSDs below a cluster root is not perfectly balanced.
"""

import json
import subprocess
import sys
from collections import namedtuple
from dataclasses import dataclass
from enum import IntEnum
from itertools import chain
from typing import Dict, Iterable, Iterator, List, Self, Tuple

import tomllib

# defining global helper constants

KiB = 1024
MiB = 1024 * KiB
GiB = 1024 * MiB


# TODO: this can be moved to common sensu check util code
class SensuStatus(IntEnum):
    # sorted from highest to lowest priority
    CRITICAL = 2
    WARN = 1
    UNKNOWN = 3
    OK = 0

    @classmethod
    def highest_status(
        cls: Self,
        previous: Self,
        new,
    ) -> "SensuStatus":
        """Returns the highest-priority exit code of the given two. Also checks for
        unknown exit code values, falling back to UNKNOWN"""
        for code in cls:
            if code in (new, previous):
                return code
        else:
            print(f"WARN: Encountered an unknown exit code of {new}.")
            return cls.UNKNOWN

    def merge(self, new_status) -> "SensuStatus":
        return self.__class__.highest_status(self, new_status)


Thresholds = namedtuple("Thresholds", ["nearfull", "full"])


# data abstractions


@dataclass
class CrushRoot:
    """represents a root in the Ceph CRUSH hierarchy. Is the parent for all disk space
    below it, which is thus shared by all pools located in that root."""

    name: str
    size: int  # in bytes
    used: int
    thresholds: Thresholds


@dataclass
class Pool:
    "a rbd pool"

    name: str
    root: CrushRoot


@dataclass
class Snapshot:
    pool: Pool
    image: str
    snapname: str
    size: int

    @property
    def restore_impact(self) -> Tuple[SensuStatus, float]:
        """expected CrushRoot utilisation after restoring this particular snapshot.
        does not consider sparse allocation, and assumes worst case of a 100%
        data block mismatch between base image and snapshot.
        returns: (sensu check exit code, expected crush root utilisation"""
        proot = self.pool.root
        fill_ratio_after_restore = (self.size + proot.used) / proot.size
        if fill_ratio_after_restore >= proot.thresholds.full:
            status_code = SensuStatus.CRITICAL
        elif fill_ratio_after_restore >= proot.thresholds.nearfull:
            status_code = SensuStatus.WARN
        else:
            status_code = SensuStatus.OK
        return (status_code, fill_ratio_after_restore)

    @property
    def report_msg(self) -> str:
        (status_code, fill_ratio_after_restore) = self.restore_impact
        # TODO: can be a structural pattern match in future python versions
        if status_code == SensuStatus.CRITICAL:
            return (
                f"CRITICAL: Restoring the snapshot "
                f"{self.pool.name}/{self.image}@{self.snapname} "
                # wording: "could", because we do not know the actual allocation ratio
                # of the snapshot, the calculation considers the worst case of 100% of
                # all snapshot blocks being allocated *and* not shared with the main
                # image (or image being flattened afterwards).
                f"with {self.size / GiB:,.2f}GiB might result in a fill "
                f"ratio of {fill_ratio_after_restore * 100:.2f}%, "
                f"exceeding the FULL threshold in cluster root {self.pool.root.name}."
            )
        elif status_code == SensuStatus.WARN:
            return (
                f"WARN: Restoring the snapshot "
                f"{self.pool.name}/{self.image}@{self.snapname} "
                f"with {self.size / GiB:,.2f}GiB might result in a fill "
                f"ratio of {fill_ratio_after_restore * 100:.2f}%, "
                f"exceeding the NEAR_FULL threshold in cluster root {self.pool.root.name}."
            )
        # NOTE: currently not printed anywhere, but we may want to add a verbose mode later
        elif status_code == SensuStatus.OK:
            return (
                "OK: Restoring the snapshot "
                f"{self.pool.name}/{self.image}@{self.snapname} "
                f"with {self.size / GiB:,.2f}GiB could just increase the "
                f"fill ratio in cluster root {self.pool.root} to "
                f"{fill_ratio_after_restore * 100:.2f}%."
            )
        else:
            return (
                f"WARN/ UNKNOWN: Unexpected status code {status_code} "
                f"for {self.pool.name}/{self.image}@{self.snapname}"
            )


def _ceph_osd_df_tree_roots() -> Iterator[dict]:
    df_tree_nodes = json.loads(
        subprocess.run(
            ["ceph", "--format", "json", "osd", "df", "tree"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    )["nodes"]
    return filter(lambda node: node["type"] == "root", df_tree_nodes)


def _rbd(*args: str) -> dict | list:
    """Convenience wrapper for better mocking
    consumers need to handle CalledProcessErrors themselfs"""
    return json.loads(
        subprocess.run(
            ("rbd", "--format", "json", *args),
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    )


def parse_pools(
    ceph_roots_raw: Iterator[dict],
    pool_roots: Dict[str, List[str]],
    thresholds: Thresholds,
) -> Tuple[SensuStatus, List[Pool]]:
    pools = []
    # keep track whether we get statistics for each specified crush root
    remaining_crush_roots = set(pool_roots.keys())
    status_code = SensuStatus.OK
    for root_data in ceph_roots_raw:
        crush_name = root_data["name"]
        try:
            remaining_crush_roots.remove(crush_name)
        except KeyError:
            # we're not interested in that crush root
            continue

        root_obj = CrushRoot(
            name=crush_name,
            size=root_data["kb"] * KiB,
            used=root_data["kb_used"] * KiB,
            thresholds=thresholds,
        )

        for pool_name in pool_roots[crush_name]:
            pools.append(Pool(pool_name, root_obj))

    if remaining_crush_roots:
        status_code = SensuStatus.UNKNOWN  # XXX
        print(
            "INFO: Unable to retrieve fill stats for some crush roots:",
            remaining_crush_roots,
        )

    return (status_code, pools)


def query_snaps(pools: List[Pool]) -> List[Snapshot]:
    all_snaps = []
    for pool in pools:
        for imgname in _rbd("ls", pool.name):
            # we need an img object to query snapshots and their size
            try:
                snaps = _rbd("snap", "ls", f"{pool.name}/{imgname}")
                for snap in snaps:
                    all_snaps.append(
                        Snapshot(
                            pool=pool,
                            image=imgname,
                            snapname=snap["name"],
                            size=snap["size"],
                        )
                    )
            except subprocess.CalledProcessError as e:
                if (
                    e.stderr
                    == f"rbd: error opening image {imgname}: (2) No such file or directory\n"
                ):
                    # as listing images and then accessing the images is not atomic, it is
                    # possible for the image to already be deleted. Ignore this, the changes
                    # will be considered at the next check run.
                    print(
                        f"INFO: Image {pool.name}/{imgname} not found, possibly has been "
                        "deleted during the check run"
                    )
                    continue
                else:
                    raise

    return all_snaps


def parse_config(argv) -> Tuple[Thresholds, dict]:
    if not len(argv) == 2:
        print(f"Usage: {argv[0]} <config.toml>")
        sys.exit(SensuStatus.CRITICAL)

    try:
        with open(argv[1], "rb") as configtoml:
            config = tomllib.load(configtoml)
    except (FileNotFoundError, PermissionError):
        print(f"Error: Unable to open file {argv[1]}.")
        sys.exit(SensuStatus.CRITICAL)
    except tomllib.TOMLDecodeError:
        print(f"Error: {argv[1]} is not a valid TOML file.")
        sys.exit(SensuStatus.CRITICAL)

    # repacking the required values serves as an implicit schema validation
    try:
        thresholds = Thresholds(
            nearfull=float(config["thresholds"]["nearfull"]),
            full=float(config["thresholds"]["full"]),
        )
        pool_roots = config["ceph_roots"]
        for root, pools in pool_roots.items():
            assert len(pools) > 0, (
                "parse_config: roots must have at least one pool"
            )
            for pool in pools:
                assert isinstance(pool, str), (
                    "parse_config: pools must be strings"
                )
    except (KeyError, ValueError, AssertionError) as ex:
        print(
            f"Error loading config file {argv[1]}: Values missing or of wrong type.\n"
            "details:", repr(ex)
        )  # fmt: skip
        sys.exit(SensuStatus.CRITICAL)

    return (thresholds, pool_roots)


def categorise_snaps(
    snaps: Iterable[Snapshot],
) -> Dict[SensuStatus, List[Snapshot]]:
    # also defines which exit codes we want to report separately in a summary
    categories: dict[SensuStatus, list[Snapshot]] = {
        SensuStatus.WARN: [],
        SensuStatus.CRITICAL: [],
    }
    for snap in snaps:
        # TODO: use case switch pattern matching
        (restore_code, _) = snap.restore_impact
        try:
            categories[restore_code].append(snap)
        except KeyError:
            # code not relevant here
            continue

    return categories


def eval_report(
    categorised_snaps: Dict[SensuStatus, List[Snapshot]],
) -> Tuple[SensuStatus, str]:
    # eval total status code _from categorised snaps only_, as it still needs to be
    # combined with potential other status results from the cluster querying functions
    status_code = SensuStatus.OK
    summary_lines = []
    report_lines = []
    nonempty_categories = (
        (cat, entries)
        for (cat, entries) in categorised_snaps.items()
        if entries
    )
    for cat, entries in nonempty_categories:
        summary_lines.append(f"{len(entries)} {cat.name} snapshot(s)")
        status_code = status_code.merge(cat)
        for entry in entries:
            report_lines.append(entry.report_msg)
    report_str = "\n".join(
        chain(
            (f"Total status: {status_code.name}",),
            summary_lines,
            ("\nDetails:",) if report_lines else (),
            report_lines,
        )
    )
    return (status_code, report_str)


def main():
    # can cause the program to exit with non-working config
    (thresholds, pool_roots) = parse_config(sys.argv)
    # phase 1: data collection
    # retrieve cluster root fill stats
    # retrieve list of images and snaps
    (status_code, pools) = parse_pools(
        _ceph_osd_df_tree_roots(), pool_roots, thresholds
    )
    all_snaps = query_snaps(pools)
    # phase 2: evaluation: filter and sort snapshots into warn categories
    reporting_snap_categories = categorise_snaps(all_snaps)

    # phase 3: reporting
    (eval_status, report_str) = eval_report(reporting_snap_categories)
    print(report_str)
    sys.exit(status_code.merge(eval_status))
