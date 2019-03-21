#! /usr/bin/env nix-shell
#! nix-shell -i python3 -p python34Packages.python -p python34Packages.requests2 -p python34Packages.click -I nixpkgs=/root/nixpkgs
#
# input sample
# {
#     "configuration":  {
#     "tls_key_password":  "P@ssw0rd",
#     "recv_buffer_size":  1048576,
#     "max_message_size":  2097152,
#     "bind_address":  "0.0.0.0",
#     "port":  12201,
#     "tls_enable":  false,
#     "use_null_delimiter":  true
#     },
#     "title":  "myNewGlobalGelfTcpInput",
#     "global":  true,
#     "type":  "org.graylog2.inputs.gelf.tcp.GELFTCPInput"
# }
# 201 -> success
# returns input id
#
# requests.post(api + '/system/inputs/', auth=(user, pw), json=data).text
# >>> '{"id":"57fe09c2ec3fa136a780adb9"}'
import click
import dateutil.parser
import json
import logging
import requests
import socket
import time


logging.basicConfig(format='%(levelname)s:%(message)s', level=logging.INFO)

log = logging.getLogger('fc-graylog')


@click.group()
@click.option('-u', '--user', default='admin', show_default=True)
@click.option('-p', '--password', default='admin', show_default=True)
@click.argument('api')
@click.pass_context
def main(ctx, api, user, password):
    graylog = requests.Session()
    graylog.auth = (user, password)
    graylog.api = api
    ctx.obj = graylog


@click.command()
@click.option('--input')
@click.option('--raw-path')
@click.option('--raw-data')
@click.pass_obj
def configure(graylog, input, raw_path, raw_data):
    """Configure a Graylog input node."""
    api = graylog.api

    if input:
        # check if there is input with this name currently configured,
        # if so return
        data = json.loads(input)
        log.info('Checking intput: %s', data['title'])
        response = graylog.get(api + '/system/cluster/node')
        response.raise_for_status()
        data['node'] = response.json()['node_id']
        response = graylog.get(api + '/system/inputs')
        response.raise_for_status()
        for _input in response.json()['inputs']:
            if _input['title'] == data['title']:
                log.info(
                    'Graylog input already configured. Updating: %s',
                    data['title'])
                response = graylog.put(
                    api + '/system/inputs/%s' % _input['id'], json=data)
                response.raise_for_status()
                break
        else:
            response = graylog.post(api + '/system/inputs', json=data)
            response.raise_for_status()
            log.info('Graylog input configured: %s', data['title'])

    if raw_path and raw_data:
        log.info('Update %s', raw_path)
        data = json.loads(raw_data)
        response = graylog.put(api + raw_path, json=data)
        response.raise_for_status()


main.add_command(configure)


@click.command()
@click.option('--socket-path')
@click.pass_obj
def collect_journal_age_metric(graylog, socket_path):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(socket_path)
    while True:
        response = graylog.get(
            graylog.api +
            '/system/metrics/org.graylog2.journal.oldest-segment')

        response.raise_for_status()
        segment_date = dateutil.parser.parse(response.json()['value'])
        response_date = dateutil.parser.parse(response.headers['date'])
        age = (response_date - segment_date).total_seconds()
        s.send(('graylog_journal_age value=%f\n' % age).encode('us-ascii'))
        time.sleep(10)


main.add_command(collect_journal_age_metric)


if __name__ == '__main__':
    main()
