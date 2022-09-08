# also copied to pkgs/fc/agent/fc/util/runners.py
import json
import os
import subprocess
import time
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
        "rbd_locktool": "rbd-locktool",
    }
)


## common management utils


def find_vg_for_mon():
    vgsys = False
    for vg in run.json.vgs():
        if vg["vg_name"].startswith("vgjnl"):
            return vg["vg_name"]
        if vg["vg_name"] == "vgsys":
            vgsys = True

    if vgsys:
        print(
            "WARNING: using volume group `vgsys` because no journal "
            "volume group was found."
        )
        return "vgsys"
    raise IndexError("No suitable volume group found.")


def find_lv_path(name):
    result = []
    for lv in run.json.lvs():
        if lv["lv_name"] == name:
            result.append(lv)
    if len(result) != 1:
        raise ValueError(f"Invalid number of LVs found: {len(result)}")
    lv = result[0]
    return f"/dev/{lv['vg_name']}/{lv['lv_name']}"


def mount_status(mountpoint):
    """Return the absolute path to the kernel device used for a given
    mountpoint.

    Returns a false value if the given path is not currently a mountpoint.

    """
    for device in run.json.lsblk_linear():
        if device["mountpoint"] == mountpoint:
            return device["name"]
    return False


def kill(pid_file):
    if not os.path.exists(pid_file):
        print(f"PID file {pid_file} not found. Not killing.")
        return

    with open(pid_file) as f:
        pid = f.read().strip()
    run.kill(pid)
    counter = 0
    while os.path.exists(f"/proc/{pid}"):
        counter += 1
        time.sleep(1)
        print(".", end="", flush=True)
        if not counter % 30:
            # We already sent a kill signal earlier so even when
            # the proc file existed the process might have
            # exited and we're fine with kill not finding the pid
            # any longer.
            run.kill(pid, check=False)
    print()
