"""Check that the largest RBD image snapshot of each Ceph cluster root can be restored,
without exceeding the near_full threshold of the cluster capacity.
Please consider that this is not a guarantee for not getting `OSD_NEARFULL` warnings,
as individual fill levels of OSDs below a cluster root is not perfectly balanced."""

import contextlib
import json
import sys
from collections import namedtuple
from time import sleep

import rados
import rbd
import toml  # replace this with tomllib when on python-3.11+

KiB = 1024
MiB = 1024 * KiB
GiB = 1024 * MiB

EXIT_OK = 0
EXIT_WARN = 1
EXIT_CRITICAL = 2
EXIT_UNKNOWN = 3

EXIT_PRIORITIES = [
    EXIT_CRITICAL,
    EXIT_WARN,
    EXIT_UNKNOWN,
    EXIT_OK,
]

Thresholds = namedtuple("thresholds", ["nearfull", "full"])


def main():
    # can cause the program to exit with non-working config
    (thresholds, pool_roots) = parse_config(sys.argv)
    with cluster_connection() as cluster:
        fill_stats = get_cluster_fillstats(cluster, pool_roots)
        largest_snaps = get_largest_snaps(cluster, pool_roots)

    sys.exit(eval_fill_warnings(fill_stats, largest_snaps, thresholds))


def parse_config(argv) -> (Thresholds, dict):
    if not len(argv) == 2:
        print(f"Usage: {argv[0]} <config.toml>")
        sys.exit(EXIT_CRITICAL)

    try:
        with open(argv[1], "rt") as configtoml:
            config = toml.load(configtoml)
    except (FileNotFoundError, PermissionError):
        print(f"Error: Unable to open file {argv[1]}.")
        sys.exit(EXIT_CRITICAL)
    except toml.TomlDecodeError:
        print(f"Error: {argv[1]} is not a valid TOML file.")
        sys.exit(EXIT_CRITICAL)

    # repacking the required values serves as an implicit schema validation
    try:
        thresholds = Thresholds(
            nearfull=float(config["thresholds"]["nearfull"]),
            full=float(config["thresholds"]["full"]),
        )
        pool_roots = config["ceph_roots"]
        for root, pools in pool_roots.items():
            assert len(pools) > 0
            for pool in pools:
                assert isinstance(pool, str)
    except (KeyError, ValueError, AssertionError):
        print(
            f"Error loading config file {argv[1]}: Values missing or of wrong type."
        )
        sys.exit(EXIT_CRITICAL)

    return (thresholds, pool_roots)


def eval_fill_warnings(cluster_fill_stats, largest_snaps, thresholds) -> int:
    """Evaluates the expected fill levels after restoring a cluster and generates the
    appropriate warnings if necessary.
    Returns the exit code equivalent to the Sensu warning urgency, calling `sys.exit` is
    left to the caller."""

    def max_exitcode(previous: int, new: int) -> int:
        """Returns the highest-priority exit code of the given two. Also checks for
        unknown exit code values, falling back to EXIT_UNKNOWN"""
        for code in EXIT_PRIORITIES:
            if code in (new, previous):
                return code
        else:
            print(f"WARN: Encountered an unknown exit code of {new}.")
            return EXIT_UNKNOWN

    exit_code = 0
    if not largest_snaps:
        print(
            "INFO: There are no snapshots in the considered pools, nothing to do."
        )
        return exit_code
    for (root, (pool, snap)) in largest_snaps.items():
        try:
            root_stats = cluster_fill_stats[root]
        except KeyError:
            print(
                f"INFO: Root {root} not in fill stats data, something is wrong here."
            )
            exit_code = max_exitcode(exit_code, EXIT_UNKNOWN)
            continue
        try:
            fill_now_bytes = int(root_stats["kb_used"] * KiB)
            total_bytes = int(root_stats["kb"] * KiB)
        except KeyError:
            print(f"INFO: Unable to get cluster fill levels for root {root}.")
            exit_code = max_exitcode(exit_code, EXIT_UNKNOWN)
            continue
        # Note: fill_now_bytes takes into account the sparseness of images and only
        # includes the actual allocated data in the cluster, while snap["size_bytes"]
        # describes the provisioned size (100% allocation). This can lead to unintuitive
        #  (but somehow correct) results.
        fill_ratio_after_restore = (
            snap["size_bytes"] + fill_now_bytes
        ) / total_bytes
        # Note: This also triggers when the cluster is above the thresholds even without
        # restoring a anapshot
        if fill_ratio_after_restore >= thresholds.full:
            print(
                f"CRITICAL: Restoring the snapshot "
                f"{pool}/{snap['imgname']}@{snap['snapname']} "
                # wording: "could", because we do not know the actual allocation ratio
                # of the snapshot, the calculation considers the worst case of 100% of
                # all snapshot blocks being allocated *and* not shared with the main
                # image (or image being flattened afterwards).
                f"with {snap['size_bytes'] / GiB :,.2f}GiB might result in a fill "
                f"ratio of {fill_ratio_after_restore * 100 :.2f}%, "
                f"exceeding the FULL threshold in cluster root {root}."
            )
            exit_code = max_exitcode(exit_code, EXIT_CRITICAL)
        elif fill_ratio_after_restore >= thresholds.nearfull:
            print(
                f"WARN: Restoring the snapshot "
                f"{pool}/{snap['imgname']}@{snap['snapname']} "
                f"with {snap['size_bytes'] / GiB :,.2f}GiB might result in a fill "
                f"ratio of {fill_ratio_after_restore * 100 :.2f}%, "
                f"exceeding the NEAR_FULL threshold in cluster root {root}."
            )
            exit_code = max_exitcode(exit_code, EXIT_WARN)
        else:
            print(
                "OK: Restoring the snapshot "
                f"{pool}/{snap['imgname']}@{snap['snapname']} "
                f"with {snap['size_bytes'] / GiB :,.2f}GiB could just increase the "
                f"fill ratio in cluster root {root} to "
                f"{fill_ratio_after_restore * 100 :.2f}%."
            )
    return exit_code


def get_largest_snaps(connection: rados.Rados, pool_roots: dict) -> dict:
    """Retrieves the largest snapshot per cluster root over all RBD pools specified for
    that root in pool_roots.
    The result is a dict of the form {cluster_name: (poolname, snapshotdata)}."""
    largest_snaps = {}
    for root, pools in pool_roots.items():
        # Right now, we only need to deal with a single rbd pool per root, but let's
        # keep this generic. As fill alerting happens at cluster root level, we need
        # to find the largest rbd snapshot from all pools of that cluster.
        root_largest_snap = root_dummy = ("dummypool", {"size_bytes": -1})
        for pool in pools:
            with contextlib.closing(connection.open_ioctx(pool)) as poolio:
                pool_largest_snap = largest_snap_per_pool(poolio, pool)
                if not pool_largest_snap:
                    print(f"INFO: Pool {pool} has no (largest) snapshots.")
                elif (
                    pool_largest_snap["size_bytes"]
                    > root_largest_snap[1]["size_bytes"]
                ):
                    root_largest_snap = (pool, pool_largest_snap)

        if root_largest_snap is not root_dummy:
            largest_snaps[root] = root_largest_snap
    return largest_snaps


def largest_snap_per_pool(poolio: rados.Ioctx, poolname: str):
    largest_snap = dummy = {"size_bytes": -1}  # a pseudo-optional value
    # in principle, only the ioctx determines the pool used. But for cleanliness always
    # instantiate a new RBD per pool
    rbdpool = rbd.RBD()
    for imgname in rbdpool.list(poolio):
        # we need an img object to query snapshots and their size
        try:
            snaps = rbd.Image(poolio, imgname).list_snaps()
            for snap in snaps:
                if snap["size"] > largest_snap["size_bytes"]:
                    largest_snap = {
                        "imgname": imgname,
                        "snapname": snap["name"],
                        "size_bytes": snap["size"],
                    }
        except rbd.ImageNotFound:
            # as listing images and then accessing the images is not atomic, it is
            # possible for the image to already be deleted. Ignore this, the changes
            # will be considered at the next check run.
            print(
                f"INFO: Image {poolname}/{imgname} not found, possibly has been "
                "deleted during the check run"
            )
            continue
    return None if largest_snap is dummy else largest_snap


def get_cluster_fillstats(connection, pool_roots):
    """Parses the cluster root stats into a more digestible dictionary structure.
    Only considers the pool roots of interest to us, specified in `pool_roots`."""
    cluster_roots = (
        node
        for node in json.loads(
            # we need to re-use the same interface as `ceph` CLI subcommands use.
            # The JSON command structure has been obtained via
            # `ceph --verbose <desired subcommand>`
            connection.mon_command(
                json.dumps(
                    {
                        "prefix": "osd df",
                        "output_method": "tree",
                        "format": "json",
                    }
                ),
                b"",
            )[1]
        )["nodes"]
        if node["type"] == "root"
    )
    root_dict = {
        root["name"]: root
        for root in cluster_roots
        if root["name"] in pool_roots
    }
    return root_dict


@contextlib.contextmanager
def cluster_connection():
    cluster = rados.Rados(conffile="/etc/ceph/ceph.conf")
    try:
        cluster.connect()
        yield cluster
    finally:
        cluster.shutdown()
