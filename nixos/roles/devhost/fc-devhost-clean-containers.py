import glob
import json
import os
import subprocess
import time

AGE_SHUTDOWN = 7 * 24 * 60 * 60
AGE_DESTROY = 30 * 24 * 60 * 60

changes = 0

for filename in glob.glob('/etc/devserver/*.json'):
    current_stat = os.stat(filename)
    age = time.time() - current_stat.st_mtime
    if age < AGE_SHUTDOWN:
        continue
    config = json.loads(open(filename, 'rb').read())
    name = config['name']
    print(f'{name} is {age:.0f}s old')
    if age > AGE_SHUTDOWN:
        print('\tshutting down')
        changes += 1
        config['enabled'] = False
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(config, f)
        os.utime(filename, (current_stat.st_atime, current_stat.st_mtime))
        subprocess.run(['nixos-container', 'stop', name])
    if age > AGE_DESTROY:
        print('\tdestroying')
        subprocess.run(['nixos-container', 'destroy', name])
        # Let the agent clean up the certificate and frontend
        # opportunistically during the next fc-manage run.
        os.unlink(filename)
        changes += 1

if changes:
    # Ensure that NixOS configs are updated so that nginx doesn't die.
    subprocess.run(['systemctl', 'start', 'fc-agent'])
