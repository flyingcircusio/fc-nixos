import json
import subprocess


def dump_secret(target, data):
    with open(target, "w") as f:
        subprocess.check_call(f"chown consul: {target}", shell=True)
        subprocess.check_call(f"chmod 700 {target}", shell=True)
        json.dump(data, f)


with open("/etc/nixos/enc.json") as f:
    enc = json.load(f)
enc_secrets = enc["parameters"]["secrets"]
secrets = {
    "acl": {
        "tokens": {
            "agent": enc_secrets["consul/agent_token"],
        },
    },
    "encrypt": enc_secrets["consul/encrypt"],
}

# General secrets
dump_secret("/etc/consul.d/secrets.json", secrets)

# Watches
with open("/etc/consul.d/watches.json.in") as f:
    cfg = json.load(f)

for watch in cfg["watches"]:
    watch["token"] = enc_secrets["consul/master_token"]

dump_secret("/etc/consul.d/watches.json", cfg)
