#! /usr/bin/env nix-shell
#! nix-shell -i python3 -p python37Packages.python -p python37Packages.requests -p python37Packages.dateutil -p python37Packages.click
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
import json
import logging
import os.path
import socket
import time

import click
import dateutil.parser
import requests

logging.basicConfig(format="%(levelname)s:%(message)s", level=logging.INFO)

log = logging.getLogger("fc-graylog")


@click.group()
@click.option("-u", "--user", default="admin", show_default=True)
@click.option("-p", "--password")
@click.option(
    "-P",
    "--password-file",
    default="/etc/local/graylog/password",
    show_default=True,
)
@click.option("--api", "-a")
@click.option(
    "-A", "--api-file", default="/etc/local/graylog/api_url", show_default=True
)
@click.pass_context
def main(ctx, api, user, password, password_file, api_file):
    graylog = requests.Session()

    if not password:
        with open(password_file) as f:
            password = f.read()

    if not api:
        with open(api_file) as f:
            api = f.read()

    graylog.auth = (user, password)
    graylog.headers = {"X-Requested-By": "cli", "Accept": "application/json"}
    graylog.api = api
    ctx.obj = graylog


@click.command()
@click.option("--input")
@click.option("--raw-path")
@click.option("--raw-data")
@click.pass_obj
def configure(graylog, input, raw_path, raw_data):
    """Configure a Graylog input node."""
    api = graylog.api

    if input:
        # check if there is input with this name currently configured,
        # if so return
        data = json.loads(input)
        log.info("Checking intput: %s", data["title"])
        response = graylog.get(api + "/system/cluster/node")
        response.raise_for_status()
        data["node"] = response.json()["node_id"]
        response = graylog.get(api + "/system/inputs")
        response.raise_for_status()
        for _input in response.json()["inputs"]:
            if _input["title"] == data["title"]:
                log.info(
                    "Graylog input already configured. Updating: %s",
                    data["title"],
                )
                response = graylog.put(
                    api + "/system/inputs/%s" % _input["id"], json=data
                )
                response.raise_for_status()
                break
        else:
            response = graylog.post(api + "/system/inputs", json=data)
            response.raise_for_status()
            log.info("Graylog input configured: %s", data["title"])

    if raw_path and raw_data:
        log.info("Update %s", raw_path)
        data = json.loads(raw_data)
        response = graylog.put(api + raw_path, json=data)
        response.raise_for_status()


main.add_command(configure)


@click.command()
@click.option("--socket-path")
@click.pass_obj
def collect_journal_age_metric(graylog, socket_path):
    """Sends journal age metrics to telegraf periodically."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(socket_path)
    while True:
        response = graylog.get(
            graylog.api + "/system/metrics/org.graylog2.journal.oldest-segment"
        )

        response.raise_for_status()
        segment_date = dateutil.parser.parse(response.json()["value"])
        response_date = dateutil.parser.parse(response.headers["date"])
        age = (response_date - segment_date).total_seconds()
        s.send(("graylog_journal_age value=%f\n" % age).encode("us-ascii"))
        time.sleep(10)


main.add_command(collect_journal_age_metric)


def handle_api_response(response, expected_status=[200], log_response=True):
    if response.status_code in expected_status:
        log.info(
            "%s (%d) %s",
            response.url,
            response.status_code,
            response.text if log_response else "",
        )
        if response.text:
            return response.json()
    elif response.status_code == 400:
        log.error("%s bad request: %s", response.url, response.text)
    else:
        log.warning(
            "%s unexpected status: %d", response.url, response.status_code
        )

    response.raise_for_status()


@click.command()
@click.argument("name")
@click.argument("config")
@click.pass_obj
def ensure_user(graylog, name, config):
    """Creates or updates a Graylog user."""
    users_url = f"{graylog.api}/users"
    user_url = f"{users_url}/{name}"
    resp = graylog.get(user_url)
    data = {
        "username": name,
        "full_name": name,
        "email": f"{name}@localhost",
        "permissions": [],
        **json.loads(config),
    }

    handle_api_response(resp, [200, 404])

    if resp.ok:
        log.info("user %s exists, updating", name)
        resp = graylog.put(user_url, json=data)
        handle_api_response(resp, [204])
    if resp.status_code == 404:
        log.info("creating user %s", name)
        resp = graylog.post(users_url, json=data)
        handle_api_response(resp, [201])


main.add_command(ensure_user)


@click.command()
@click.argument("name")
@click.argument("config")
@click.pass_obj
def ensure_role(graylog, name, config):
    """Creates or updates a Graylog role"""
    roles_url = f"{graylog.api}/roles"
    role_url = f"{roles_url}/{name}"
    resp = graylog.get(role_url)
    data = {"name": name, **json.loads(config)}

    handle_api_response(resp, [200, 404])

    if resp.ok:
        log.info("role %s exists, updating", name)
        resp = graylog.put(role_url, json=data)
        handle_api_response(resp)
    if resp.status_code == 404:
        log.info("creating role %s", name)
        resp = graylog.post(roles_url, json=data)
        handle_api_response(resp, [201])


main.add_command(ensure_role)


@click.command()
@click.argument("path")
@click.argument("raw")
@click.option("--method", type=click.Choice(["POST", "PUT"]), default="PUT")
@click.option("--expected-status", "-s", multiple=True, default=[200], type=int)
@click.pass_obj
def call(graylog, path, raw, method, expected_status):
    """Runs an arbitrary API PUT/POST request."""
    data = json.loads(raw)
    resp = graylog.request(method, graylog.api + path, json=data)
    handle_api_response(resp, expected_status)


main.add_command(call)


@click.command()
@click.argument("path")
@click.option("--expected-status", "-s", multiple=True, default=[200])
@click.option("--log-response/--no-log-response", "-l", default=False)
@click.pass_obj
def get(graylog, path, expected_status, log_response):
    """Runs an arbitrary API GET request."""
    resp = graylog.get(graylog.api + path)
    result = handle_api_response(resp, expected_status, log_response)
    print(resp.text)


main.add_command(get)

if __name__ == "__main__":
    main()
