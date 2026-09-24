import random
import time
from subprocess import CalledProcessError
from typing import Any, Self

from .cluster import Cluster
from .rbdimage import RBDImage


class Pools(object):
    """Container for Ceph pool listings.

    `Pools` caches already obtained result to speed up lookups.
    """

    def __init__(self, cluster: Cluster):
        self.cluster: Cluster = cluster
        self._cache: dict[str, Pool] = {}
        self._names: set[str] = set()

    def lookup(self, pool):
        """Deprecated. Use pools[poolname] instead."""
        return self[pool]

    def __getitem__(self, pool):
        if pool in self._cache:
            return self._cache[pool]
        p = self._cache[pool] = Pool(pool, self.cluster)
        return p

    def image_exists(self, pool, image):
        """Returns True if `image` is present in `pool`."""
        try:
            return bool(self[pool][image])
        except KeyError:
            return False

    def names(self) -> set[str]:
        """Returns all pool names."""
        if self._names:
            return self._names
        pools = self.cluster.ceph_json("osd", "lspools")
        self._names = set(p["poolname"] for p in pools)
        return self._names

    def all(self):
        """Returns list of all pools in the cluster as Pool objects."""
        return (self[p] for p in self.names())

    def __iter__(self):
        """Short form for `for i in pools.all():`."""
        return self.all()

    def pick(self):
        """Returns randomly picked pool (as Pool object)."""
        return self[random.choice(list(self.names()))]

    def create(self, pool: str) -> "Pool":
        """Adds new pool to the Ceph cluster."""
        self.cluster.ceph(
            "osd",
            "pool",
            "create",
            pool,
            str(self.cluster.default_pg_num()),
        )
        if self._names:
            self._names.add(pool)
        return self[pool]


class Pool(object):
    """Single pool listing.

    The contents of the pool is queried via `rbd` and then broken up for
    easy access.
    """

    def __init__(self, poolname: str, cluster: Cluster):
        self.name = poolname
        self.cluster: Cluster = cluster
        self._images = None
        self._pg_num: int | None = None
        self._pg_num_min: int | None = None
        self._pgp_num: int | None = None
        self._size: int | None = None

    def get(self, imagename):
        """Deprecated. Use pool[imagename] instead."""
        return self[imagename]

    def __getitem__(self, imagename):
        """Looks up image `imagename`."""
        if not self._images:
            self._images = self.load()
        return self._images[imagename]

    @property
    def images(self):
        """Returns an iterator over all images in the pool."""
        if not self._images:
            self._images = self.load()
        return list(self._images.values())

    def load(self):
        """Loads all images found in this pool."""
        images = {}
        poollist = self._rbd_query()
        for i in poollist:
            image = RBDImage.from_dict(i)
            images[image.name] = image
        return images

    def _rbd_query(self):
        try:
            return self.cluster.rbd_json("ls", "-l", self.name)
        except CalledProcessError as e:
            if e.returncode == 2 and "error opening pool" in e.stderr:
                raise KeyError(self.name, e.output)
            if e.returncode == 2 and "doesn't contain rbd images" in e.stderr:
                return []
            raise

    def fix_options(self):
        """Adapt important pool properties to most up-to-date values."""
        self.cluster.ceph(
            "osd",
            "pool",
            "set",
            self.name,
            "hashpspool",
            "1",
        )

    @property
    def pg_num(self):
        if self._pg_num:
            return self._pg_num
        pginfo = self.cluster.ceph_json(
            "osd",
            "pool",
            "get",
            self.name,
            "pg_num",
        )
        self._pg_num = int(pginfo["pg_num"])
        return self._pg_num

    @pg_num.setter
    def pg_num(self, value):
        """Sets the number of PGs.

        This may take a while as pgp_num (the effective number) can only
        be changed after the PGs have been created in the cluster.
        """
        self.cluster.ceph(
            "osd",
            "pool",
            "set",
            self.name,
            "pg_num",
            str(value),
        )
        self._pg_num = int(value)
        # XXX: Since Ceph Nautilus: as long as pgp_num and pg_num currently match, pgp_num will automatically track any pg_num changes
        # We might be able to simplfy this here. Letting Ceph itself track the pgp changes is even preferrable, as this is done in smaller steps.
        self.pgp_num = value

    @property
    def pg_num_min(self) -> int | None:
        if self._pg_num_min:
            return self._pg_num_min
        try:
            pginfo = self.cluster.ceph_json(
                "osd",
                "pool",
                "get",
                self.name,
                "pg_num_min",
            )
            self._pg_num_min = int(pginfo["pg_num_min"])
        except CalledProcessError as e:
            if e.returncode == 2 and b"is not set on pool" in e.stderr:
                # still the default value
                self._pg_num_min = None
            else:
                raise

        return self._pg_num_min

    @pg_num_min.setter
    def pg_num_min(self, value: int | None):
        """Sets the minimum number of PGs assigned by the pg_autoscaler."""
        value_numerical = (
            value if value else 0
        )  # setting `0` unsets the property back to default
        self.cluster.ceph(
            "osd",
            "pool",
            "set",
            self.name,
            "pg_num_min",
            str(value_numerical),
        )
        self._pg_num_min = int(value) if value else None

    @property
    def pgp_num(self):
        if self._pgp_num:
            return self._pgp_num
        pginfo = self.cluster.ceph_json(
            "osd",
            "pool",
            "get",
            self.name,
            "pgp_num",
        )
        self._pgp_num = int(pginfo["pgp_num"])
        return self._pgp_num

    @pgp_num.setter
    def pgp_num(self, value):
        retry = 0
        max_retries = 40
        while retry < max_retries:
            time.sleep(min([30, 1.2**retry]))

            try:
                self.cluster.ceph(
                    "osd",
                    "pool",
                    "set",
                    self.name,
                    "pgp_num",
                    str(value),
                )
            except CalledProcessError:
                retry += 1
            else:
                self._pgp_num = int(value)
                return
        raise RuntimeError("max retries exceeded while setting pgp_num")

    @property
    def size(self) -> int:
        if self._size:
            return self._size
        pginfo = self.cluster.ceph_json(
            "osd",
            "pool",
            "get",
            self.name,
            "size",
        )
        self._size = int(pginfo["size"])
        return self._size

    @size.setter
    def size(self, value: int) -> None:
        if (num_hosts := self.cluster.num_hosts_per_root()) < value:
            raise ValueError(
                f"Insufficient amount of hosts: {value} required, {num_hosts} available."
            )
        else:
            self.cluster.ceph(
                "osd", "pool", "set", self.name, "size", str(value)
            )
            self._size = value

    @property
    def size_total_gb(self):
        return sum(i.size_gb for i in self.images if not i.snapshot)

    def snap_rm(self, rbdimage):
        self.cluster.rbd(
            "snap",
            "rm",
            f"{self.name}/{rbdimage.image}@{rbdimage.snapshot}",
        )
        self._images = None

    def image_rm(self, rbdimage):
        assert rbdimage.snapshot is None
        self.cluster.rbd("rm", f"{self.name}/{rbdimage.image}")
        self._images = None

    def delete(self):
        if self.images:
            raise RuntimeError(
                "cannot delete non-empty pool {} -- remove images first".format(
                    self.name
                )
            )
        self.cluster.ceph(
            "osd",
            "pool",
            "delete",
            self.name,
            self.name,
            "--yes-i-really-really-mean-it",
        )

    def ensure_balanceable(self):
        """For all pools that have a default value of `pg_num_min`, set that
        property to `1`.
        We have many pools that are almost empty by design, like `rbd`. The
        pg_autoscaler assigns at least `pg_num_min` PGs to each pool, which
        defaults to `32` and is a waste of PGs in smaller clusters. Let's allow
        going down to 1 PG if needed. Unfortunately there is no configurable
        default value.
        This behaviour *might* improve in Ceph Quincy.
        """
        if not self.pg_num_min:
            self.pg_num_min = 1
