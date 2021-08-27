"""Update the in-core cephx client keys from the keyring file."""

import base64
import datetime
import hashlib
import json
import logging
import os
import re
import struct
import subprocess
import sys
import tempfile
import textwrap

import fc.util.configfile
import fc.util.directory

#####################
# Ceph key management


class Key(object):
    """Low-level management of Ceph (binary) key data.
    """

    type_ = 1
    sec = 0
    nsec = 0

    secret = None

    additional_salt = b''

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
            "sha512",
            self.additional_salt + passphrase,
            b"",
            10**6,
            dklen=length)
        self.secret = hash


class InstalledKey(object):

    entity = None
    key = None
    caps = None

    @classmethod
    def from_mon_data(cls, data):
        self = cls()
        self.entity = data['entity']
        self.key = data['key']
        self.caps = data['caps']
        return self

    def compare_key(self):
        return self.entity, self.key, self.caps

    def __eq__(self, other):
        if isinstance(other, (InstalledKey, KeyConfig)):
            return self.compare_key() == other.compare_key()
        raise TypeError(f"Invalid comparison with {other!r}")


class InstalledKeys(object):
    """Interface to cephx' live (in-core) key store."""

    known_keys = None

    def __init__(self):
        self.known_keys = {}
        out = subprocess.check_output(['ceph', 'auth', 'list', '-f', 'json'],
                                      stderr=subprocess.PIPE)
        data = json.loads(out)['auth_dump']
        for record in data:
            self.known_keys[record['entity']] = InstalledKey.from_mon_data(
                record)

    def ensure(self, keyconfig):
        print(f'\n{keyconfig.entity}:')

        if keyconfig.entity in self.known_keys:
            known_key = self.known_keys[keyconfig.entity]
            if known_key == keyconfig:
                print('\tNOOP (Key in store and matching.)')
                return
            else:
                print('\tUPDATE (Key in store but not matching.)')
        else:
            print('\tUPDATE (Key not in store)')

        # FYI No need (and no ability) to manage the umask here as tempfile
        # ensures this that temporary files are private by default.
        tmp_keyring = tempfile.NamedTemporaryFile(mode='w+')
        tmp_keyring.write(f"""
[{keyconfig.entity}]
    key = "{keyconfig.key.to_string()}"
    {keyconfig.render_capabilities()}
""")
        tmp_keyring.flush()
        try:
            output = subprocess.check_output(
                ['ceph', 'auth', 'import', '-i', tmp_keyring.name],
                stderr=subprocess.STDOUT).decode('ascii')
        except Exception as e:
            print(textwrap.indent(e.output.decode('ascii', '\t')))
            raise
        else:
            print(textwrap.indent(output, '\t'))


class KeyConfig(object):
    """High level key representation including capabilities,
    ids, and interaction with Ceph and text keyring files.
    """

    filename = None

    # Ceph knows two concepts:
    # 1. 'usernames' and 'entities'. The include the type like 'client.admin'
    # 2. 'names' and 'ids'. They do not include the type like 'admin'

    entity = None
    capabilities = None
    additional_salt = b''

    def __init__(self, id):
        self.key = Key()
        self.key.additional_salt = self.additional_salt
        for attr in ['filename', 'entity']:
            value = getattr(self, attr).format(id=id)
            setattr(self, attr, value)

    def compare_key(self):
        return self.entity, self.key.to_string(), self.capabilities

    def save_client_keyring(self):
        f = fc.util.configfile.ConfigFile(
            self.filename, mode=0o600, diff=False)
        f.write(f"""\
[{self.entity}]
key = {self.key.to_string()}
""")
        f.commit()

    def render_capabilities(self):
        result = ""
        for type_, cap in self.capabilities.items():
            result += f'\t caps {type_} = "{cap}"\n'
        return result


class ClientKey(KeyConfig):

    filename = '/etc/ceph/ceph.client.{id}.keyring'
    entity = 'client.{id}'
    capabilities = {'mon': 'allow r', 'osd': 'allow rwx'}


class RGWKey(KeyConfig):

    filename = '/etc/ceph/ceph.client.radosgw.{id}.keyring'
    entity = 'client.radosgw.{id}'
    capabilities = {'mon': 'allow rwx', 'osd': 'allow rwx'}
    additional_salt = b'rgw'


ROLE_KEYS = {
    'backyserver': {ClientKey},
    'kvm_host': {ClientKey},
    'ceph_rgw': {RGWKey}}


class KeyManager(object):

    def mon_update_client_keys(self):
        errors = None

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

            # Check which keys to install:
            keys_to_install = set()

            for role in node['roles']:
                keys_to_install.update(ROLE_KEYS.get(role, set()))

            if not keys_to_install:
                continue

            for key_factory in keys_to_install:
                keyconfig = key_factory(node['name'])
                keyconfig.key.update_secret(
                    node['parameters']['secret_salt'].encode('ascii'))
                try:
                    keystore.ensure(keyconfig)
                except Exception:
                    logging.exception('', exc_info=True)
                    errors = True
        if errors:
            print("Encountered errors. See log / output")
            sys.exit(1)

    def generate_client_keyring(self):
        enc = fc.util.directory.load_default_enc_json()

        keys_to_install = set()
        for role in enc['roles']:
            keys_to_install.update(ROLE_KEYS.get(role, set()))

        for key_factory in keys_to_install:
            keyconfig = key_factory(enc['name'])
            keyconfig.key.update_secret(
                enc['parameters']['secret_salt'].encode('ascii'))
            keyconfig.save_client_keyring()
