"""Unified client access to fc.directory."""
import contextlib
import functools
import json
import re
import urllib.parse
import xmlrpc.client

import stamina


def load_default_enc_json():
    with open("/etc/nixos/enc.json") as f:
        return json.load(f)


class ScreenedProtocolError(xmlrpc.client.ProtocolError):
    def __init__(self, url, *args, **kw):
        url = re.sub(r":(\S+)@", ":PASSWORD@", url)
        super(ScreenedProtocolError, self).__init__(url, *args, **kw)


RETRY_EXCEPTIONS = (
    ScreenedProtocolError,
    xmlrpc.client.Fault,
    # OSError also covers exceptions from the socket module, ssl.SSLError
    # and ConnectionError.
    OSError,
)


class DirectoryAPI(xmlrpc.client.ServerProxy):
    def __init__(self, url, retry=False):
        """
        url: directory API URL to connect to
        retry: retry failed API requests automatically using exponential backoff.
        """
        self.retry = retry
        super().__init__(url, allow_none=True, use_datetime=True)

    def __getattr__(self, name):
        """Magic method dispatcher from ServerProxy with added retry logic."""
        method = super().__getattr__(name)

        if not self.retry:
            return method

        # This function wrapper is needed to make the Stamina decorator work.
        def wrapper(*args):
            return method(*args)

        # Stamina uses __qualname__ for retry logging, so let's set it to a
        # recognizable value.
        wrapper.__qualname__ = "DirectoryAPI." + name

        retry = stamina.retry(
            on=RETRY_EXCEPTIONS, wait_exp_base=10, attempts=2
        )
        return retry(wrapper)

    def __repr__(self):
        """ServerProxy.__repr__ leaks the directory password, override it."""
        host = self._ServerProxy__host.split("@")[1]
        handler = self._ServerProxy__handler
        return f"Directory API ({host}{handler})"


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

    return DirectoryAPI(url, retry=True)


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
