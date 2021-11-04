import re
import json
import pprint
import pysensu
import pysensu.api
import smtplib
import socket
import sys
import time

emergency_email = 'PLACEHOLDER'

sensu_password = ''
services_json = json.load(open('/etc/nixos/services.json', 'r'))
for entry in services_json:
    if (entry['address'] == f'{socket.gethostname()}.gocept.net'
            and entry['service'] == 'sensuserver-api'):
        sensu_password = str(entry['password'])


def sendmail(from_addr,
             to_addr_list,
             subject,
             message,
             smtpserver='mail.gocept.net'):
    header = 'From: %s\n' % from_addr
    header += 'To: %s\n' % ','.join(to_addr_list)
    header += 'Subject: %s\n\n' % subject
    message = header + message

    server = smtplib.SMTP(smtpserver)
    server.starttls()
    # server.login(login,password)
    server.sendmail(from_addr, to_addr_list, message)
    server.quit()


sensu = pysensu.api.SensuAPI('http://localhost:4567',
                             username='sensuserver-api',
                             password=sensu_password)


def log(msg, client, check_name, *formats):
    msg = msg.format(*formats)
    print('{}/{}: {msg}'.format(client, check_name, msg=msg), flush=True)


def have_stash_or_silenced(stashes, client, check_name):
    own_stash_path = 'bpi/{}'.format(client)
    silenced_path = 'silenced/{}/{}'.format(client, check_name)
    silenced_path_host = 'silenced/{}'.format(client)
    for stash_path in [own_stash_path, silenced_path, silenced_path_host]:
        if stash_path in stashes:
            return True
    return False


# VM HEALTH
need_ok = set(['keepalive', 'ssh'])
host_specific_need_ok = set([
    ('test24', 'postgresql'),
])

# blackbee, bitebox is monitored/alerted via statuspage.
client_ignore = re.compile(r'''
((litprod|\w+stag|\w+test|demo\w+|\w+dev|blackbee|bb3prod|test|bitebox)\d\d)
''')

log('Monitoring checks on all VMs: {}', sys.argv[0], 'init', need_ok)
log('Monitoring checks on specific VMs: {}', sys.argv[0], 'init',
    host_specific_need_ok)

logged = set()

while True:
    events = sensu.get_events()

    stashes = sensu.get_stashes()
    stashes = {stash['path']: stash for stash in stashes}

    hosts = {}
    for event in events:
        check_name = event['check']['name']
        client = event['client']['name']
        if client_ignore.match(client):
            continue
        if (check_name in need_ok
                or (client, check_name) in host_specific_need_ok):
            if event['check']['status'] >= 2:  # CRITICAL
                # if client == 'nordforsk02': import pdb; pdb.set_trace()
                print(
                    client,
                    check_name,
                )
                history = ''.join(event['check']['history'])
                if not history.endswith('2222222222'):
                    # not yet
                    log('CRITICAL, below threshold. History: {}', client,
                        check_name, history)
                    continue
                if have_stash_or_silenced(stashes, client, check_name):
                    if client not in logged:
                        log('Stash found or is silenced. No alarm.', client,
                            check_name)
                        logged.add(client)
                    continue
                if client not in logged:
                    log('CRITICAL. Sending alarm.', client, check_name)
                    logged.add(client)
                hosts.setdefault(client, []).append(event['check'])
            else:
                logged.discard(client)

    for host, events in hosts.items():
        # Instead of this we could feed this back into sensu as a new
        # check-event.
        sendmail(
            'admin+sensu@flyingcircus.io', [emergency_email],
            '{} critical: {}'.format(host,
                                     ', '.join(e['name'] for e in events)),
            '<pre>\n' + pprint.pformat(events) + '\n</pre>')

        sensu.create_stash(
            dict(
                # If it's not solved within 4 hours, issue new ticket.
                expire=3600 * 4,
                path='bpi/{}'.format(host),
                content=dict(source='BPI')))
    time.sleep(60)
