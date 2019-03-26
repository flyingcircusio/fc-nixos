#!/usr/bin/env python3

import argparse
import os
import os.path as p
import pwd
import subprocess

HOME = os.getenv('HOME', pwd.getpwuid(os.getuid()).pw_dir)
RPATH = '$ORIGIN:$ORIGIN/..:$ORIGIN/../lib:{}/.nix-profile/lib'.format(HOME)


def _verbose(msg):
    print(msg)


def run(args):
    if args.verbose:
        verbose = _verbose
    else:
        verbose = lambda msg: None
    if args.prepend_rpath:
        rpath = '{}:{}'.format(args.prepend_rpath, RPATH)
    else:
        rpath = RPATH

    for d in args.DIR:
        for (path, dirs, files) in os.walk(d):
            for f in files:
                if not f.endswith('.so'):
                    continue
                full = p.join(path, f)
                if not os.access(full, os.X_OK):
                    continue
                headers = subprocess.check_output(['objdump', '-x', full]).\
                    decode('utf-8')
                if 'RPATH' in headers or 'RUNPATH' in headers:
                    verbose('{}: rpath present, skipping'.format(full))
                    continue
                verbose('{}: setting rpath'.format(full))
                subprocess.check_call(['patchelf', '--set-rpath', rpath, full])


def main():
    a = argparse.ArgumentParser(epilog='''\
Add an rpath (actually RUNPATH) field to all .so files which don't have one.
The rpath contains the most common local lib dirs as well as the calling user's
nix profile (default: {}). Custom rpath elements can be prepended.
'''.format(RPATH))
    a.add_argument('DIR', nargs='+', help='directories to walk recursively')
    a.add_argument('--prepend-rpath', '-p', metavar='PATH',
                   help='RPATH elements to prepend to the standard rpath list')
    a.add_argument('--verbose', '-v', default=False, action='store_true',
                   help="tell what's going on")
    run(a.parse_args())


if __name__ == '__main__':
    main()
