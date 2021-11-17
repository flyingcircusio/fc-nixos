import glob
import json
import os
import subprocess
import time

AGE_SHUTDOWN = 7 * 24 * 60 * 60
AGE_DESTROY = 30 * 24 * 60 * 60

for filename in glob.glob('/etc/devserver/*.json'):
    age = time.time() - os.stat(filename).st_mtime
    if age < AGE_SHUTDOWN:
        continue
    config = json.loads(open(filename, 'rb').read())
    name = config['name']
    print(f'{name} is {age:.0f}s old')
    if age > AGE_SHUTDOWN:
        print('\tshutting down')
        subprocess.run(['nixos-container', 'stop', name])
    if age > AGE_DESTROY:
        print('\tdestroying')
        subprocess.run(['nixos-container', 'destroy', name])
        # Let the agent clean up the certificate and frontend
        # opportunistically during the next fc-manage run.
        os.unlink(filename)
