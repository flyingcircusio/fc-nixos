import json
import random
import time

from .rbdimage import RBDImage


class Pools(object):
    """Container for Ceph pool listings.

    `Pools` caches already obtained result to speed up lookups.
    """

    def __init__(self, cluster):
        self.cluster = cluster
        self._cache = {}
        self._names = set()

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

    def names(self):
        """Returns all pool names."""
        if self._names:
            return self._names
        out, _err = self.cluster.ceph_osd(["lspools"], ignore_dry_run=True)
        pools = json.loads(out.strip())
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

    def create(self, pool):
        """Adds new pool to the Ceph cluster."""
        self.cluster.ceph_osd(
            ["pool", "create", pool, str(self.cluster.default_pg_num())]
        )
        if self._names:
            self._names.add(pool)


class Pool(object):
    """Single pool listing.

    The contents of the pool is queried via `rbd` and then broken up for
    easy access.
    """

    def __init__(self, poolname, cluster):
        self.name = poolname
        self.cluster = cluster
        self._images = None
        self._pg_num = None
        self._pgp_num = None

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
        poollist = json.loads(self._rbd_query())
        for i in poollist:
            image = RBDImage.from_dict(i)
            images[image.name] = image
        return images

    def _rbd_query(self):
        stdout, stderr, returncode = self.cluster.rbd(
            ["--format=json", "ls", "-l", self.name],
            accept_failure=True,
            ignore_dry_run=True,
        )
        if returncode == 0:
            return stdout
        if returncode == 2 and "error opening pool" in stderr:
            raise KeyError(self.name, stdout)
        if returncode == 2 and "doesn't contain rbd images" in stderr:
            return "[]"
        raise RuntimeError("rbd execution failed", stdout, stderr, returncode)

    def fix_options(self):
        """Adapt important pool properties to most up-to-date values."""
        self.cluster.ceph_osd(["pool", "set", self.name, "hashpspool", "1"])

    @property
    def pg_num(self):
        if self._pg_num:
            return self._pg_num
        out = self.cluster.ceph_osd(
            ["pool", "get", self.name, "pg_num"], ignore_dry_run=True
        )
        pginfo = json.loads(out[0])
        self._pg_num = int(pginfo["pg_num"])
        return self._pg_num

    @pg_num.setter
    def pg_num(self, value):
        """Sets the number of PGs.

        This may take a while as pgp_num (the effective number) can only
        be changed after the PGs have been created in the cluster. Note
        that you can only increase the number of PGs and never decrease
        it again. Note that this method may take a while to complete.
        """
        self.cluster.ceph_osd(["pool", "set", self.name, "pg_num", str(value)])
        self._pg_num = int(value)
        self.pgp_num = value

    @property
    def pgp_num(self):
        if self._pgp_num:
            return self._pgp_num
        out = self.cluster.ceph_osd(
            ["pool", "get", self.name, "pgp_num"], ignore_dry_run=True
        )
        pginfo = json.loads(out[0])
        self._pgp_num = int(pginfo["pgp_num"])
        return self._pgp_num

    @pgp_num.setter
    def pgp_num(self, value):
        retry = 0
        max_retries = 40
        while retry < max_retries:
            time.sleep(min([30, 1.2**retry]))
            out, err, returncode = self.cluster.ceph_osd(
                ["pool", "set", self.name, "pgp_num", str(value)],
                accept_failure=True,
            )
            if returncode == 0:
                self._pgp_num = int(value)
                return
            retry += 1
        raise RuntimeError("max retries exceeded while setting pgp_num")

    @property
    def size_total_gb(self):
        return sum(i.size_gb for i in self.images if not i.snapshot)

    def snap_rm(self, rbdimage):
        self.cluster.rbd(
            [
                "snap",
                "rm",
                "{}/{}@{}".format(
                    self.name, rbdimage.image, rbdimage.snapshot
                ),
            ]
        )
        self._images = None

    def image_rm(self, rbdimage):
        assert rbdimage.snapshot is None
        self.cluster.rbd(["rm", "{}/{}".format(self.name, rbdimage.image)])
        self._images = None

    def delete(self):
        if self.images:
            raise RuntimeError(
                "cannot delete non-empty pool {} -- remove "
                "images first".format(self.name)
            )
        self.cluster.ceph_osd(
            [
                "pool",
                "delete",
                self.name,
                self.name,
                "--yes-i-really-really-mean-it",
            ]
        )
