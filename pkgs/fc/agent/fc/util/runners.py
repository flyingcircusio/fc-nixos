# copied from pkgs/fc/ceph/src/fc/ceph/util.py
import json
import subprocess
from subprocess import PIPE

## runner utils

LVM_QUERY_OPTIONS = ("--reportformat", "json", "--units", "b", "--nosuffix")


class JSONRunner(object):
    """Create simplified calls for tools that provide JSON CLIs.

    The idea here is that you can call "run.json.foobar" and
    a) the tool is automatically invoked in a way that it outputs
    JSON and b) that the JSON output is automatically returned
    in a Python structure and c) maybe even massaged a bit for
    usability for the caller.

    """

    def __init__(self, runner):
        self.runner = runner

    def __run__(self, name, *args, **kw):
        result = getattr(self.runner, name)(*args, **kw)
        result = json.loads(result)
        return result

    # Tool-specific overrides to ensure that the invoked tools return JSON and
    # to massage their output for usability.

    def sfdisk(self, *args, **kw):
        return self.__run__("sfdisk", "-J", *args, **kw)

    def ceph(self, *args, **kw):
        return self.__run__("ceph", "-f", "json", *args, **kw)

    def pvs(self, *args, **kw):
        result = self.__run__("pvs", *(LVM_QUERY_OPTIONS + args), **kw)
        return result["report"][0]["pv"]

    def vgs(self, *args, **kw):
        result = self.__run__("vgs", *(LVM_QUERY_OPTIONS + args), **kw)
        return result["report"][0]["vg"]

    def lvs(self, *args, **kw):
        result = self.__run__("lvs", *(LVM_QUERY_OPTIONS + args), **kw)
        return result["report"][0]["lv"]

    def lsblk(self, *args, **kw):
        return self.__run__("lsblk", "-J", *args, **kw)["blockdevices"]

    def lsblk_linear(self, *args, **kw):
        """Return a linearized version of the nested lsblk structure.

        To keep the resulting data structure simple we remove the
        "children" keys from each record - otherwise every node would show
        up twice, once in a tree structure and once as a top level entry.

        """
        result = []
        candidates = self.lsblk(*args, *kw)
        while candidates:
            candidate = candidates.pop()
            candidates.extend(candidate.pop("children", []))
            result.append(candidate)
        return result

    def rbd(self, *args, **kw):
        return self.__run__("rbd", "--format", "json", *args, **kw)


class Runner(object):
    def __init__(
        self,
        aliases={},
        default_options=dict(check=True, stdout=PIPE, stderr=PIPE),
    ):
        self.__aliases = aliases
        self.default_options = default_options

        self.json = JSONRunner(self)

    def __getattr__(self, name):
        name = self.__aliases.get(name, name)

        def callable(*args, **kw):
            options = self.default_options.copy()
            options.update(kw)

            print("$", name, " ".join(args), flush=True)

            check = options["check"]
            options["check"] = True

            try:
                return subprocess.run((name,) + args, **options).stdout
            except subprocess.CalledProcessError as e:
                print("> return code:", e.returncode)
                print("> stdout:")
                print(e.stdout.decode("ascii", errors="replace"))
                print("> stderr:")
                print(e.stderr.decode("ascii", errors="replace"))
                if check:
                    raise

        return callable


run = Runner(
    aliases={
        "ceph_osd": "ceph-osd",
        "ceph_mgr": "ceph-mgr",
        "ceph_mon": "ceph-mon",
        "ceph_authtool": "ceph-authtool",
        "mkfs_xfs": "mkfs.xfs",
    }
)
