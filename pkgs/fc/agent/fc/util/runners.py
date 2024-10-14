# copied from pkgs/fc/ceph/src/fc/ceph/util.py
import json
import shlex
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

    def radosgw_admin(self, *args, **kw):
        return self.__run__("radosgw-admin", "--format", "json", *args, **kw)

    def rbd(self, *args, **kw):
        return self.__run__("rbd", "--format", "json", *args, **kw)


class RedactedValue(str):
    def __new__(cls, content):
        obj = super().__new__(cls, "<REDACTED>")
        obj.orig = content
        return obj


class Runner(object):
    def __init__(
        self,
        aliases={},
        default_options=dict(check=True, stdout=PIPE, stderr=PIPE),
    ):
        self.__aliases = aliases
        self.default_options = default_options

        self.json = JSONRunner(self)

    def redacted(self, value):
        return RedactedValue(value)

    def __getattr__(self, name):
        name = self.__aliases.get(name, name)

        def callable(*args, **kw):
            silent_errors = kw.pop("silent_errors", lambda x: False)
            options = self.default_options.copy()
            options.update(kw)

            print("$", name, shlex.join(args), flush=True)

            check = options["check"]

            # Always cause the actual subprocess call to have `check` set
            # but if the options passed into this call don't set check, then
            # we only resort to logging the error and not re-raising it.
            options["check"] = True

            call_args = [
                (arg.orig if isinstance(arg, RedactedValue) else arg)
                for arg in args
            ]

            try:
                return subprocess.run(
                    [
                        name,
                    ]
                    + call_args,
                    **options,
                ).stdout
            except subprocess.CalledProcessError as e:
                if not silent_errors(e.returncode, e.stdout, e.stderr):
                    known_secret_values = [
                        x.orig for x in args if isinstance(x, RedactedValue)
                    ]

                    print("> return code:", e.returncode)
                    print("> stdout:")
                    print(
                        self._redact_secrets(
                            known_secret_values,
                            e.stdout.decode("ascii", errors="replace"),
                        )
                    )
                    print("> stderr:")
                    print(
                        self._redact_secrets(
                            known_secret_values,
                            e.stderr.decode("ascii", errors="replace"),
                        )
                    )
                if check:
                    raise

        return callable

    @staticmethod
    def _redact_secrets(secrets: list[str], text: str) -> str:
        for secret in secrets:
            text = text.replace(secret, "<REDACTED>")
        return text


run = Runner(
    aliases={
        "ceph_osd": "ceph-osd",
        "ceph_mgr": "ceph-mgr",
        "ceph_mon": "ceph-mon",
        "ceph_authtool": "ceph-authtool",
        "mkfs_xfs": "mkfs.xfs",
        "radosgw_admin": "radosgw-admin",
    }
)
