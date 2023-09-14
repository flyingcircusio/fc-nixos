import filecmp
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path

import pystemd.systemd1
from rich import print

required_env_vars = {"encServicesPath", "mungeKeyFile"}
missing_env_vars = required_env_vars - os.environ.keys()

os.umask(0o0266)

if missing_env_vars:
    print(f"error: missing environment variables: {missing_env_vars}")
    sys.exit(1)

enc_services_path = Path(os.environ["encServicesPath"])
if not enc_services_path.exists():
    print(f"error: services files at {enc_services_path} is missing")
    sys.exit(2)

munge_key_path = Path(os.environ["mungeKeyFile"])

with open(enc_services_path) as f:
    enc_services = json.load(f)

controller_service = [
    s for s in enc_services if s["service"] == "slurm-controller-controller"
]

if not controller_service:
    print("error: service not found, is the slurm-controller role enabled?")
    sys.exit(3)

service_pw = controller_service[0]["password"] + "\n"
munge_key = hashlib.sha256(service_pw.encode()).hexdigest()[:64]

key_dir = munge_key_path.parent
if not key_dir.exists():
    print(f"init: creating key dir at {key_dir}")
    key_dir.mkdir()

tmp_key = key_dir / "tmp-set-munge-key"
tmp_key.unlink(missing_ok=True)
with open(tmp_key, "w") as wf:
    wf.write(munge_key)
    wf.flush()
    os.fsync(wf)

shutil.chown(tmp_key, "munge", "munge")

munged_unit = pystemd.systemd1.Unit("munged.service")
munged_unit.load()
print(f"munged.service state: {munged_unit.Unit.ActiveState}")

if not munge_key_path.exists():
    print(f"init: no previous munge key found at {munge_key_path}")
    os.replace(tmp_key, munge_key_path)
    print("init: new key set")

elif not filecmp.cmp(tmp_key, munge_key_path, shallow=False):
    print(f"change: key in {munge_key_path} differs from expected key")
    os.replace(tmp_key, munge_key_path)
    print("change: key updated")

    if munged_unit.Unit.ActiveState == b"active":
        print("change: munged is running, restarting to pick up the new key")
        munged_unit.Unit.Restart(b"replace")
else:
    print("skip: key is already up-to-date.")
    tmp_key.unlink()

print("fc-set-munge-key finished")
