"""Update the in-core cephx client keys from the keyring file."""

import base64
import datetime
import hashlib
import os
import re
import struct
import subprocess
import sys
import tempfile

import fc.util.configfile
import fc.util.directory

#####################
# Ceph key management

CAPS = "--cap mon 'allow r' --cap osd 'allow rwx'"


class Key(object):

    type_ = 1
    sec = 0
    nsec = 0

    secret = None

    @classmethod
    def from_string(cls, key):
        result = Key()
        key = base64.b64decode(key)
        result.type_, result.sec, result.nsec, result.length = struct.unpack(
            "<HIIH", key[:12])

        secret = key[12:]
        assert len(secret) == result.length
        result.secret = secret

        return result

    @property
    def time(self):
        return datetime.datetime.fromtimestamp(self.sec + self.nsec * 10**-9)

    def to_string(self):
        header = struct.pack("<HIIH", self.type_, self.sec, self.nsec,
                             len(self.secret))
        return base64.b64encode(header + self.secret).decode('ascii')

    def update_secret(self, passphrase, length=16):
        hash = hashlib.pbkdf2_hmac(
            "sha512", passphrase, b"", 10**6, dklen=length)
        self.secret = hash

    def to_file(self, filename, name, caps):
        # Add key to keyring file
        subprocess.check_call(
            'ceph-authtool {filename} -C -n "{name}" {caps} -a "{key}"'.format(
                filename=filename, name=name, caps=caps, key=self.to_string()),
            shell=True)


class InstalledKeys(object):
    """Interface to cephx' live (in-core) key store."""

    known_keys = ()

    def __init__(self):
        self.known_keys = set()
        out = subprocess.check_output(['ceph', 'auth', 'list'],
                                      stderr=subprocess.PIPE).decode('ascii')
        for line in out.splitlines():
            if line.startswith('client.'):
                self.known_keys.add(line.strip())

    def add(self, name, keyring):
        subprocess.check_call([
            'ceph', 'auth', 'add', name, '--in-file', keyring])


#########################
# Main transaction script

CLIENT_ROLES = {'backyserver', 'ceph_mon', 'ceph_osd', 'ceph_rgw', 'kvm_host'}


class KeyManager(object):

    def mon_update_client_keys(self):
        keystore = InstalledKeys()

        enc = fc.util.directory.load_default_enc_json()

        location = enc['parameters']['location']
        rg = enc['parameters']['resource_group']

        directory = fc.util.directory.connect()
        for node in directory.list_nodes(location):
            if node['parameters']['resource_group'] != rg:
                continue
            if node['parameters']['environment_class'] != 'NixOS':
                continue
            if not set(node['roles']).intersection(CLIENT_ROLES):
                continue
            print("=" * len(node['name']))
            print(node['name'])
            key_name = 'client.' + node['name']
            if key_name in keystore.known_keys:
                print('\tkey already in place')
                continue
            key = Key()
            key.update_secret(
                node['parameters']['secret_salt'].encode('ascii'))
            key_file = tempfile.NamedTemporaryFile()
            key.to_file(key_file.name, key_name, CAPS)
            print(
                '\tadding key {} to in-core cephx key store'.format(key_name))
            keystore.add(key_name, key_file.name)

    def generate_client_key(self):
        enc = fc.util.directory.load_default_enc_json()
        node_name = enc['name']

        key = Key()
        key.update_secret(enc['parameters']['secret_salt'].encode('ascii'))

        f = fc.util.configfile.ConfigFile(
            f'/etc/ceph/ceph.client.{node_name}.keyring', 0o600)
        f.write(f"""\
[client.{node_name}]
key = {key.to_string()}
""")
        f.commit()
