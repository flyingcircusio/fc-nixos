import textwrap
import unittest.mock
from unittest.mock import MagicMock

data_correct = """LUKS header information
Version:       	2
Epoch:         	8
Metadata area: 	16384 [bytes]
Keyslots area: 	16744448 [bytes]
UUID:          	3e2649b4-88c9-4b3f-acf5-edcc380ecc23
Label:         	(no label)
Subsystem:     	(no subsystem)
Flags:       	(no flags)

Data segments:
  0: crypt
	offset: 16777216 [bytes]
	length: (whole device)
	cipher: aes-xts-plain64
	sector: 4096 [bytes]

Keyslots:
  0: luks2
	Key:        512 bits
	Priority:   normal
	Cipher:     aes-xts-plain64
	Cipher key: 512 bits
	PBKDF:      argon2id
	Time cost:  4
	Memory:     1023865
	Threads:    4
	Salt:       ec e0 7a bf 23 d1 b0 13 ac 97 b3 8d 7b 6e 5c 4f
	            21 a0 c1 19 f1 1e f7 0d 2b 67 3d e8 8a 4c 51 47
	AF stripes: 4000
	AF hash:    sha256
	Area offset:32768 [bytes]
	Area length:258048 [bytes]
	Digest ID:  0
  1: luks2
	Key:        512 bits
	Priority:   normal
	Cipher:     aes-xts-plain64
	Cipher key: 512 bits
	PBKDF:      argon2id
	Time cost:  4
	Memory:     989547
	Threads:    4
	Salt:       7a 07 6e a9 20 ac 1e 8a 6b 87 4d 26 51 66 d1 ce
	            f8 35 21 9a 2e 8d dc b6 9b d5 50 b8 f2 e1 11 3f
	AF stripes: 4000
	AF hash:    sha256
	Area offset:290816 [bytes]
	Area length:258048 [bytes]
	Digest ID:  0
Tokens:
Digests:
  0: pbkdf2
	Hash:       sha256
	Iterations: 75851
	Salt:       3b 44 80 a2 6f 29 26 01 98 bb a2 92 cc 6e bc 7c
	            df a9 e2 b2 90 ad 5e 4a e2 75 bf 9e ac 3f 81 59
	Digest:     76 11 6a c0 53 28 aa 6c 89 a9 24 52 7a d9 51 39
	            b4 d9 0e 91 50 2c 5a d4 ab df a2 6a 98 8f b1 ed"""

data_incorrect = """LUKS header information
Version:       	2
Epoch:         	8
Metadata area: 	16384 [bytes]
Keyslots area: 	16744448 [bytes]
UUID:          	3e2649b4-88c9-4b3f-acf5-edcc380ecc23
Label:         	(no label)
Subsystem:     	(no subsystem)
Flags:       	(no flags)

Data segments:
  0: crypt
	offset: 16777216 [bytes]
	length: (whole device)
	cipher: blowfish
	sector: 4096 [bytes]

Keyslots:
  0: luks2
	Key:        256 bits
	Priority:   normal
	Cipher:     chacha-20
	Cipher key: 256 bits
	PBKDF:      argon2id
	Time cost:  4
	Memory:     1023865
	Threads:    4
	Salt:       ec e0 7a bf 23 d1 b0 13 ac 97 b3 8d 7b 6e 5c 4f
	            21 a0 c1 19 f1 1e f7 0d 2b 67 3d e8 8a 4c 51 47
	AF stripes: 4000
	AF hash:    sha256
	Area offset:32768 [bytes]
	Area length:258048 [bytes]
	Digest ID:  0
  3: luks2
	Key:        512 bits
	Priority:   normal
	Cipher:     aes-xts-plain64
	Cipher key: 512 bits
	PBKDF:      SHAKE382
	Time cost:  4
	Memory:     989547
	Threads:    4
	Salt:       7a 07 6e a9 20 ac 1e 8a 6b 87 4d 26 51 66 d1 ce
	            f8 35 21 9a 2e 8d dc b6 9b d5 50 b8 f2 e1 11 3f
	AF stripes: 4000
	AF hash:    sha256
	Area offset:290816 [bytes]
	Area length:258048 [bytes]
	Digest ID:  0
Tokens:
Digests:
  0: pbkdf2
	Hash:       sha256
	Iterations: 75851
	Salt:       3b 44 80 a2 6f 29 26 01 98 bb a2 92 cc 6e bc 7c
	            df a9 e2 b2 90 ad 5e 4a e2 75 bf 9e ac 3f 81 59
	Digest:     76 11 6a c0 53 28 aa 6c 89 a9 24 52 7a d9 51 39
	            b4 d9 0e 91 50 2c 5a d4 ab df a2 6a 98 8f b1 ed"""


def test_check_cipher_ok():
    from fc.ceph.luks.checks import check_cipher

    assert list(check_cipher(data_correct.splitlines())) == []


def test_check_cipher_error():
    from fc.ceph.luks.checks import check_cipher

    assert list(check_cipher(data_incorrect.splitlines())) == [
        "cipher: chacha-20 does not match aes-xts-plain64"
    ]
    assert list(check_cipher([])) == [
        "Unable to check cipher correctness, no `Cipher:` found in dump"
    ]
    assert list(check_cipher(["gar", "bage"])) == [
        "Unable to check cipher correctness, no `Cipher:` found in dump"
    ]


def test_check_key_slots_exactly_1_and_0_ok():
    from fc.ceph.luks.checks import check_key_slots_exactly_1_and_0

    assert (
        list(check_key_slots_exactly_1_and_0(data_correct.splitlines())) == []
    )


def test_check_key_slots_exactly_1_and_0_error():
    from fc.ceph.luks.checks import check_key_slots_exactly_1_and_0

    assert list(
        check_key_slots_exactly_1_and_0(data_incorrect.splitlines())
    ) == ["keyslots: unexpected configuration ({0, 3})"]
    assert list(check_key_slots_exactly_1_and_0([])) == [
        "keyslots: unexpected configuration (set())"
    ]
    assert list(check_key_slots_exactly_1_and_0(["gar", "bage"])) == [
        "keyslots: unexpected configuration (set())"
    ]


def test_check_512_bit_keys_ok():
    from fc.ceph.luks.checks import check_512_bit_keys

    assert list(check_512_bit_keys(data_correct.splitlines())) == []


def test_check_512_bit_keys_error():
    from fc.ceph.luks.checks import check_512_bit_keys

    assert list(check_512_bit_keys(data_incorrect.splitlines())) == [
        "keysize: 256 bits does not match expected 512 bits"
    ]
    assert list(check_512_bit_keys([])) == [
        "Unable to check key size correctness, no `Key:` found in dump"
    ]
    assert list(check_512_bit_keys(["gar", "bage"])) == [
        "Unable to check key size correctness, no `Key:` found in dump"
    ]


def test_check_pbkdf_is_argon2id_ok():
    from fc.ceph.luks.checks import check_pbkdf_is_argon2id

    assert list(check_pbkdf_is_argon2id(data_correct.splitlines())) == []


def test_check_pbkdf_is_argon2id_error():
    from fc.ceph.luks.checks import check_pbkdf_is_argon2id

    assert list(check_pbkdf_is_argon2id(data_incorrect.splitlines())) == [
        "pbkdf: SHAKE382 does not match expected argon2id"
    ]
    assert list(check_pbkdf_is_argon2id([])) == [
        "Unable to check PBKDF correctness, no `PBKDF:` found in dump"
    ]
    assert list(check_pbkdf_is_argon2id(["gar", "bage"])) == [
        "Unable to check PBKDF correctness, no `PBKDF:` found in dump"
    ]


def test_check_integration_ok(monkeypatch, capsys):
    from fc.ceph.luks.manage import LuksDevice, LUKSKeyStoreManager

    luksdevice_mock = MagicMock(
        return_value=[
            LuksDevice(
                base_blockdev="/dev/mapper/foo",
                name="testdev1",
                mountpoint="/mnt/foo",
            ),
            LuksDevice(
                base_blockdev="/dev/vgbar/holygrail",
                name="testdev2",
                mountpoint="/mnt/bar",
            ),
        ]
    )
    monkeypatch.setattr(LuksDevice, "filter_cryptvolumes", luksdevice_mock)

    monkeypatch.setattr(
        "fc.ceph.luks.Cryptsetup.cryptsetup",
        MagicMock(return_value=data_correct.encode("utf-8")),
    )

    assert LUKSKeyStoreManager.check_luks("*", header=None) == 0

    captured = capsys.readouterr()
    assert captured.out == textwrap.dedent(
        """\
        Checking testdev1:
        check_cipher: OK
        check_key_slots_exactly_1_and_0: OK
        check_512_bit_keys: OK
        check_pbkdf_is_argon2id: OK
        Checking testdev2:
        check_cipher: OK
        check_key_slots_exactly_1_and_0: OK
        check_512_bit_keys: OK
        check_pbkdf_is_argon2id: OK
        """
    )
    assert captured.err == ""


def test_check_integration_error(monkeypatch, capsys):
    from fc.ceph.luks.manage import LuksDevice, LUKSKeyStoreManager

    luksdevice_mock = MagicMock(
        return_value=[
            LuksDevice(
                base_blockdev="/dev/mapper/foo",
                name="testdev1",
                mountpoint="/mnt/foo",
            ),
            LuksDevice(
                base_blockdev="/dev/vgbar/holygrail",
                name="testdev2",
                mountpoint="/mnt/bar",
            ),
        ]
    )
    monkeypatch.setattr(LuksDevice, "filter_cryptvolumes", luksdevice_mock)

    class DumpMock:
        def __init__(self):
            self.side_effects = iter([data_incorrect.encode("utf-8"), b""])

        def __call__(self, *args, **kwargs):
            return next(self.side_effects)

    monkeypatch.setattr("fc.ceph.luks.Cryptsetup.cryptsetup", DumpMock())

    assert LUKSKeyStoreManager.check_luks("*", header=None) == 1

    captured = capsys.readouterr()
    assert captured.out == textwrap.dedent(
        """\
        Checking testdev1:
        check_cipher: cipher: chacha-20 does not match aes-xts-plain64
        check_key_slots_exactly_1_and_0: keyslots: unexpected configuration ({0, 3})
        check_512_bit_keys: keysize: 256 bits does not match expected 512 bits
        check_pbkdf_is_argon2id: pbkdf: SHAKE382 does not match expected argon2id
        Checking testdev2:
        check_cipher: Unable to check cipher correctness, no `Cipher:` found in dump
        check_key_slots_exactly_1_and_0: keyslots: unexpected configuration (set())
        check_512_bit_keys: Unable to check key size correctness, no `Key:` found in """
        + """
        dump
        check_pbkdf_is_argon2id: Unable to check PBKDF correctness, no `PBKDF:` found in
        dump
        """
    )
    assert captured.err == ""
