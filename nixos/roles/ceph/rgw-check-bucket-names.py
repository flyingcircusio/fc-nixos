"""
check if bucket names adhere to constraints of
https://github.com/ceph/ceph/blob/ab8cff83a099d8d77d6d952c57363435a5b7d92a/doc/radosgw/s3/bucketops.rst#L23

This is a stub to get started with bucket name migrations.
"""

import ipaddress
import json
import re
import sys


def is_ip(name):
    try:
        ipaddress.ip_address(name)
        return True
    except ValueError:
        return False


LABEL_RE = re.compile(r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?$")


def validate(name, seen):
    errors = []
    if name in seen:
        errors.append("not unique")
    if not (3 <= len(name) <= 63):
        errors.append(f"length {len(name)} not in [3,63]")
    if is_ip(name):
        errors.append("formatted as IP address")
    if re.search(r"[A-Z_]", name):
        errors.append("contains uppercase or underscore")
    if not re.match(r"^[a-z0-9]", name):
        errors.append("must start with lowercase letter or number")
    for label in name.split("."):
        if not LABEL_RE.match(label):
            errors.append(f"invalid label '{label}'")
            break
    return errors


buckets = json.load(sys.stdin)

seen = set()
failures = {}

for name in buckets:
    errors = validate(name, seen)
    if errors:
        failures[name] = errors
    seen.add(name)

print(json.dumps(failures, indent=2))

if failures:
    sys.exit(1)

sys.exit(0)
