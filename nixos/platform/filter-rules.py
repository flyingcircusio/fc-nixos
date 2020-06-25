#!/usr/bin/env python3
import fileinput
import re
import shlex
import sys
import os.path as p

R_ALLOWED = re.compile(r'^(ip(6|46)?tables .*)?''$')

ADDR_V4_ALLOWED = re.compile(r'^[0-9.\/\-]+$')
ADDR_V6_ALLOWED = re.compile(r'^[0-9a-fA-F\/\-]+:[0-9a-fA-F\:\/\-]*$')


# We currently only filter hostnames in the '-s' and '-d' options. There
# are some more obscure candidates around but I'm leaving them out for now
# because they don't imply that they are actually doing DNS resolution:
#
# [!] --ctorigsrc address[/mask]
# [!] --ctorigdst address[/mask]
# [!] --ctreplsrc address[/mask]
# [!] --ctrepldst address[/mask]
# [!] --src-range from[-to]
# [!] --dst-range from[-to]
# [!] --vaddr address[/mask]
# [!] --tunnel-src addr[/mask]
# [!] --tunnel-dst addr[/mask]
# --rt-0-addrs addr[,addr...]
# --to-destination [ipaddr[-ipaddr]][:port[-port]]
# --hmark-src-prefix cidr
# --hmark-dst-prefix cidr
# --to address[/mask]
# --to-source [ipaddr[-ipaddr]][:port[-port]]
# --on-ip address

def find_arguments_with_values(options, args):
    for option in options:
        if option not in args:
            continue
        value = args[args.index(option)+1]
        yield option, value


def exit_with_error(message, line):
    fn = fileinput.filename()
    ln = fileinput.lineno()
    print('File "{fn}", line {ln}\n'
          '  {line}\n\n'
          'Error: {message}'.format(
              message=message, line=line.strip(), fn=fn, ln=ln),
          file=sys.stderr)
    sys.exit(1)


for line in fileinput.input():
    line = line.strip()
    if line.startswith('#'):
        print(line)
        continue
    atoms = list(shlex.quote(s) for s in shlex.split(line.strip()))
    m = R_ALLOWED.match(' '.join(atoms))

    # Is this an iptables command?
    if not (m and m.group(1)):
        exit_with_error('only iptables statements or comments allowed', line)

    # Are there any hostnames in there?
    for option, value in find_arguments_with_values(
            ['-s', '--source', '-d', '--destination'], atoms):
        if ADDR_V4_ALLOWED.match(value):
            continue
        if ADDR_V6_ALLOWED.match(value):
            continue
        exit_with_error('hostnames are not allowed as addresses', line)

    # Are we using a default chain? Don't.
    for option, value in find_arguments_with_values(
            ['-A', '-C', '-D', '-I', '-R', '-S', '-F', '-L', '-Z', '-N', '-X',
            '-P', '-E'], atoms):
        if value in ['INPUT', 'OUTPUT', 'FORWARD', 'PREROUTING', 'POSTROUTING'
                      'SECMARK', 'CONNSECMARK']:
            exit_with_error('builtin chains are not allowed here', line)

    print(m.group(1))
