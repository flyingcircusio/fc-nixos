"""Unified client access to fc.directory."""

import contextlib
import json
import re
import urllib.parse
import xmlrpc.client


def load_default_enc_json():
    with open("/etc/nixos/enc.json") as f:
        return json.load(f)


class ScreenedProtocolError(xmlrpc.client.ProtocolError):
    def __init__(self, url, *args, **kw):
        url = re.sub(r":(\S+)@", ":PASSWORD@", url)
        super(ScreenedProtocolError, self).__init__(url, *args, **kw)


def connect(enc=None, ring=1):
    """Returns XML-RPC directory connection.

    The directory secret is read from `/etc/nixos/enc.json`.
    Alternatively, the parsed JSON content can be passed directly as
    dict.

    Selects ring0/ring1 API according to the `ring` parameter. Giving `max`
    results in selecting the highest ring available according to the ENC.
    """
    if xmlrpc.client.ProtocolError is not ScreenedProtocolError:
        xmlrpc.client.ProtocolError = ScreenedProtocolError
    if not enc:
        enc = load_default_enc_json()
    if ring == "max":
        ring = enc["parameters"]["directory_ring"]

    base_url = enc["parameters"].get(
        "directory_url", "https://directory.fcio.net/v2/api"
    )
    url_parts = urllib.parse.urlsplit(base_url)

    url = "".join(
        [
            url_parts.scheme + "://",
            enc["name"] + ":" + enc["parameters"]["directory_password"] + "@",
            url_parts.netloc,
            url_parts.path,
        ]
    )

    if ring == 1:
        url += "/rg-" + enc["parameters"]["resource_group"]

    return xmlrpc.client.Server(url, allow_none=True, use_datetime=True)


@contextlib.contextmanager
def directory_connection(enc_path):
    """Execute the associated block with a directory connection."""
    enc = None
    if enc_path:
        with open(enc_path) as f:
            enc = json.load(f)
    yield connect(enc)


def directory_cli():
    import sys

    cmd = sys.argv[1]
    d = connect(ring="max")
    exec(cmd)


def is_node_in_service(directory, node) -> bool:
    return directory.lookup_node(node)["parameters"]["servicing"]
