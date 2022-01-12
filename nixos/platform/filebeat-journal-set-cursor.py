import json
import sys
import subprocess
from pathlib import Path

if len(sys.argv) != 3:
    raise RuntimeError(
        "Needs exactly two arguments: registry_path legacy_registry_path"
    )

registry_path = Path(sys.argv[1])
legacy_registry_path = Path(sys.argv[2])
cursor_path = registry_path / "log.json"
meta_path = registry_path / "meta.json"

if not registry_path.exists():
    registry_path.mkdir(parents=True)

if not registry_path.is_dir():
    raise RuntimeError(f"{registry_path} must be a directory!")

if not meta_path.exists():
    with open(meta_path, "w") as wf:
        json.dump({"version": "1"}, wf)

if cursor_path.exists():
    sys.exit(0)

if legacy_registry_path.exists():
    print("Migrating old journalbeat cursor to new structure.")
    # It's actually YAML...
    prefix = "  cursor: "
    with open(legacy_registry_path) as f:
        for line in f.readlines():
            if line.startswith(prefix):
                cursor = line.removeprefix(prefix).strip()
                break
else:
    print(
        "Journal cursor not present, initalizing it to the end of the journal."
    )
    journal_out = subprocess.run(
        ["journalctl", "-o", "json", "-n1"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    cursor = json.loads(journal_out)["__CURSOR"]

cursor_structure = {
    "k": "journald::everything::LOCAL_SYSTEM_JOURNAL",
    "v": {"cursor": {"position": cursor, "version": 1}},
}

with open(cursor_path, "w") as wf:
    json.dump({"op": "set", "id": 1}, wf)
    wf.write("\n")
    json.dump(cursor_structure, wf)
    wf.write("\n")
