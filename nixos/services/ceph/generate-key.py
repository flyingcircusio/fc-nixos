"""Generate a ceph key.

Call with a secret
"""

import base64
import datetime
import hashlib
import struct
import sys

# Structure:
#
# type        u16     16bit       2 byte
# created     utime_t             8 byte
# length      u16     16bit       2 byte
# secret                         16 byte


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
        hash = hashlib.pbkdf2_hmac("sha512",
                                   passphrase,
                                   b"",
                                   10**6,
                                   dklen=length)
        self.secret = hash


k = Key()
k.update_secret(sys.argv[1].encode('ascii'))
print(k.to_string())
