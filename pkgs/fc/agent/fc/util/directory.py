"""Unified client access to fc.directory."""

import contextlib
import json
import re
import xmlrpc.client

DIRECTORY_URL_RING0 = (
    'https://{enc[name]}:{enc[parameters][directory_password]}@'
    'directory.fcio.net/v2/api')

DIRECTORY_URL_RING1 = (
    'https://{enc[name]}:{enc[parameters][directory_password]}@'
    'directory.fcio.net/v2/api/rg-{enc[parameters][resource_group]}')


def load_default_enc_json():
    with open('/etc/nixos/enc.json') as f:
        return json.load(f)


class ScreenedProtocolError(xmlrpc.client.ProtocolError):

    def __init__(self, url, *args, **kw):
        url = re.sub(r':(\S+)@', ':PASSWORD@', url)
        super(ScreenedProtocolError, self).__init__(url, *args, **kw)


def connect(enc_data=None, ring=1):
    """Returns XML-RPC directory connection.

    The directory secret is read from `/etc/nixos/enc.json`.
    Alternatively, the parsed JSON content can be passed directly as
    dict.

    Selects ring0/ring1 API according to the `ring` parameter. Giving `max`
    results in selecting the highest ring available according to the ENC.
    """
    if not xmlrpc.client.ProtocolError is ScreenedProtocolError:
        xmlrpc.client.ProtocolError = ScreenedProtocolError
    if not enc_data:
        enc_data = load_default_enc_json()
    if ring == 'max':
        ring = enc_data['parameters']['directory_ring']
    url = {0: DIRECTORY_URL_RING0, 1: DIRECTORY_URL_RING1}[ring]
    return xmlrpc.client.Server(
        url.format(enc=enc_data), allow_none=True, use_datetime=True)


@contextlib.contextmanager
def directory_connection(enc_path):
    """Execute the associated block with a directory connection."""
    enc_data = None
    if enc_path:
        with open(enc_path) as f:
            enc_data = json.load(f)
    yield connect(enc_data)


def directory_cli():
    import sys
    cmd = sys.argv[1]
    d = connect(ring='max')
    exec(cmd)
