import json
import subprocess

with open("/etc/nixos/enc.json") as f:
    enc = json.load(f)
enc_secrets = enc["parameters"]["secrets"]
secrets = {"acl": {"tokens": {"master": enc_secrets["consul/master_token"]}}}
target_file = "/etc/consul.d/server-secrets.json"
with open(target_file, "w") as f:
    subprocess.check_call(f"chown consul: {target_file}", shell=True)
    subprocess.check_call(f"chmod 700 {target_file}", shell=True)
    json.dump(secrets, f)
