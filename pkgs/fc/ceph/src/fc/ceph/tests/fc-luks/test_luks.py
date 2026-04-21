import hashlib
import pathlib
from io import StringIO
from textwrap import dedent
from unittest import mock
from subprocess import CalledProcessError

import fc.ceph.luks
import pytest

# extracted from cartman06
LV_DUMMY_DATA = [
    {
        "lv_name": "ceph-mgr-crypted",
        "vg_name": "vgjnl00",
        "lv_attr": "-wi-ao----",
        "lv_size": "8.00g",
        "pool_lv": "",
        "origin": "",
        "data_percent": "",
        "metadata_percent": "",
        "move_pv": "",
        "mirror_log": "",
        "copy_percent": "",
        "convert_lv": "",
    },
    {
        "lv_name": "ceph-mon-crypted",
        "vg_name": "vgjnl00",
        "lv_attr": "-wi-ao----",
        "lv_size": "8.00g",
        "pool_lv": "",
        "origin": "",
        "data_percent": "",
        "metadata_percent": "",
        "move_pv": "",
        "mirror_log": "",
        "copy_percent": "",
        "convert_lv": "",
    },
    {
        "lv_name": "ceph-osd-0-wal-crypted",
        "vg_name": "vgjnl00",
        "lv_attr": "-wi-ao----",
        "lv_size": "1.00g",
        "pool_lv": "",
        "origin": "",
        "data_percent": "",
        "metadata_percent": "",
        "move_pv": "",
        "mirror_log": "",
        "copy_percent": "",
        "convert_lv": "",
    },
    {
        "lv_name": "ceph-osd-0-block-crypted",
        "vg_name": "vgosd-0",
        "lv_attr": "-wi-ao----",
        "lv_size": "<556.91g",
        "pool_lv": "",
        "origin": "",
        "data_percent": "",
        "metadata_percent": "",
        "move_pv": "",
        "mirror_log": "",
        "copy_percent": "",
        "convert_lv": "",
    },
    {
        "lv_name": "ceph-osd-0-crypted",
        "vg_name": "vgosd-0",
        "lv_attr": "-wi-ao----",
        "lv_size": "1.00g",
        "pool_lv": "",
        "origin": "",
        "data_percent": "",
        "metadata_percent": "",
        "move_pv": "",
        "mirror_log": "",
        "copy_percent": "",
        "convert_lv": "",
    },
    {
        "lv_name": "ceph-osd-0-wal-backup-crypted",
        "vg_name": "vgosd-0",
        "lv_attr": "-wi-a-----",
        "lv_size": "1.00g",
        "pool_lv": "",
        "origin": "",
        "data_percent": "",
        "metadata_percent": "",
        "move_pv": "",
        "mirror_log": "",
        "copy_percent": "",
        "convert_lv": "",
    },
]

LSBLK_JSON = """
[
  {
    "name": "sda1",
    "path": "/dev/sda1",
    "type": "part",
    "mountpoint": null,
    "children": [
      {
        "name": "sda",
        "path": "/dev/sda",
        "type": "disk",
        "mountpoint": null
      }
    ]
  },
  {
    "name": "sda2",
    "path": "/dev/sda2",
    "type": "part",
    "mountpoint": "/boot",
    "children": [
      {
        "name": "sda",
        "path": "/dev/sda",
        "type": "disk",
        "mountpoint": null
      }
    ]
  },
  {
    "name": "sdc1",
    "path": "/dev/sdc1",
    "type": "part",
    "mountpoint": null,
    "children": [
      {
        "name": "sdc",
        "path": "/dev/sdc",
        "type": "disk",
        "mountpoint": null
      }
    ]
  },
  {
    "name": "sr0",
    "path": "/dev/sr0",
    "type": "rom",
    "mountpoint": null
  },
  {
    "name": "vgsys-root",
    "path": "/dev/mapper/vgsys-root",
    "type": "lvm",
    "mountpoint": "/",
    "children": [
      {
        "name": "sda4",
        "path": "/dev/sda4",
        "type": "part",
        "mountpoint": null,
        "children": [
          {
            "name": "sda",
            "path": "/dev/sda",
            "type": "disk",
            "mountpoint": null
          }
        ]
      }
    ]
  },
  {
    "name": "vgsys-tmp",
    "path": "/dev/mapper/vgsys-tmp",
    "type": "lvm",
    "mountpoint": "/tmp",
    "children": [
      {
        "name": "sda4",
        "path": "/dev/sda4",
        "type": "part",
        "mountpoint": null,
        "children": [
          {
            "name": "sda",
            "path": "/dev/sda",
            "type": "disk",
            "mountpoint": null
          }
        ]
      }
    ]
  },
  {
    "name": "vgkeys-keys",
    "path": "/dev/mapper/vgkeys-keys",
    "type": "lvm",
    "mountpoint": "/mnt/keys",
    "children": [
      {
        "name": "sda3",
        "path": "/dev/sda3",
        "type": "part",
        "mountpoint": null,
        "children": [
          {
            "name": "sda",
            "path": "/dev/sda",
            "type": "disk",
            "mountpoint": null
          }
        ]
      }
    ]
  },
  {
    "name": "vgosd--5-ceph--osd--5--wal--backup--crypted",
    "path": "/dev/mapper/vgosd--5-ceph--osd--5--wal--backup--crypted",
    "type": "lvm",
    "mountpoint": null,
    "children": [
      {
        "name": "sdb1",
        "path": "/dev/sdb1",
        "type": "part",
        "mountpoint": null,
        "children": [
          {
            "name": "sdb",
            "path": "/dev/sdb",
            "type": "disk",
            "mountpoint": null
          }
        ]
      }
    ]
  },
  {
    "name": "backy",
    "path": "/dev/mapper/backy",
    "type": "crypt",
    "mountpoint": "/srv/backy",
    "children": [
      {
        "name": "sdb1",
        "path": "/dev/sdb1",
        "type": "part",
        "mountpoint": null,
        "children": [
          {
            "name": "sdb",
            "path": "/dev/sdb",
            "type": "disk",
            "mountpoint": null
          }
        ]
      }
    ]
  },
  {
    "name": "ceph-mon",
    "path": "/dev/mapper/ceph-mon",
    "type": "crypt",
    "mountpoint": "/srv/ceph/mon/ceph-patty",
    "children": [
      {
        "name": "vgsys-ceph--mon--crypted",
        "path": "/dev/mapper/vgsys-ceph--mon--crypted",
        "type": "lvm",
        "mountpoint": null,
        "children": [
          {
            "name": "sda4",
            "path": "/dev/sda4",
            "type": "part",
            "mountpoint": null,
            "children": [
              {
                "name": "sda",
                "path": "/dev/sda",
                "type": "disk",
                "mountpoint": null
              }
            ]
          }
        ]
      }
    ]
  },
  {
    "name": "ceph-mgr",
    "path": "/dev/mapper/ceph-mgr",
    "type": "crypt",
    "mountpoint": "/srv/ceph/mgr/ceph-patty",
    "children": [
      {
        "name": "vgsys-ceph--mgr--crypted",
        "path": "/dev/mapper/vgsys-ceph--mgr--crypted",
        "type": "lvm",
        "mountpoint": null,
        "children": [
          {
            "name": "sda4",
            "path": "/dev/sda4",
            "type": "part",
            "mountpoint": null,
            "children": [
              {
                "name": "sda",
                "path": "/dev/sda",
                "type": "disk",
                "mountpoint": null
              }
            ]
          }
        ]
      }
    ]
  }
]
"""


@pytest.fixture
def mock_LUKSKeyStoreManager(monkeypatch, tmpdir):
    class LUKSKeyStoreMock(fc.ceph.luks.LUKSKeyStore):
        def admin_key_for_input(*args, **kwargs):
            return "foo"

    def do_nothing(*args, **kwargs):
        pass

    monkeypatch.setattr(
        "fc.ceph.util.run.json.lvs", (lambda *args, **kwargs: LV_DUMMY_DATA)
    )
    monkeypatch.setattr(
        "fc.ceph.util.run.json.lsblk", (lambda *args, **kwargs: [])
    )
    keyman = fc.ceph.luks.manage.LUKSKeyStoreManager()

    keystoremock = LUKSKeyStoreMock()
    keystoremock.local_key_dir = tmpdir
    keyman._KEYSTORE = keystoremock
    keyman._do_rekey = do_nothing
    return keyman


@pytest.fixture
def mock_cryptsetup_isLuks(monkeypatch):
    class CryptsetupIsLuksMock:
        known_luks_devices: set
        illegal_devices: set

        def __init__(self):
            self.known_luks_devices = set()
            self.illegal_devices = set()

        def __call__(self, *args, **kwargs):
            assert args[0] == "isLuks", (
                f"only isLuks is properly mocked by this object; args {args}, kwargs {kwargs}"
            )

            assert kwargs["check"], (
                "isLuks only makes sense when checking the return code"
            )
            if (dev := args[1]) in self.illegal_devices:
                raise CalledProcessError(
                    returncode=4,
                    cmd=f"cryptsetup isLuks {dev}",
                    output=f"Device {dev} does not exist or access denied.",
                )
            if (dev := args[1]) in self.known_luks_devices:
                return ""
            else:
                raise CalledProcessError(
                    returncode=1, cmd=f"cryptestup isLuks {dev}", output=""
                )

    c_mock = CryptsetupIsLuksMock()
    monkeypatch.setattr("fc.ceph.util.run.cryptsetup", c_mock)
    return c_mock


def test_detect_cryptdevices_only_active():
    import json

    from fc.ceph.luks import manage

    assert set(
        manage.LuksDevice.detect_cryptdevices(
            json.loads(LSBLK_JSON), only_active=True
        )
    ) == set(
        (
            manage.LuksDevice(
                base_blockdev="/dev/mapper/vgsys-ceph--mon--crypted",
                base_blockdev_name="vgsys-ceph--mon--crypted",
                luks_name="ceph-mon",
                mountpoint="/srv/ceph/mon/ceph-patty",
                header=None,
            ),
            manage.LuksDevice(
                base_blockdev="/dev/sdb1",
                base_blockdev_name="sdb1",
                luks_name="backy",
                mountpoint="/srv/backy",
                header=None,
            ),
            manage.LuksDevice(
                base_blockdev="/dev/mapper/vgsys-ceph--mgr--crypted",
                base_blockdev_name="vgsys-ceph--mgr--crypted",
                luks_name="ceph-mgr",
                mountpoint="/srv/ceph/mgr/ceph-patty",
                header=None,
            ),
        )
    )
    assert manage.LuksDevice.detect_cryptdevices([], only_active=True) == []
    # disks, but no crypt and no children
    assert (
        manage.LuksDevice.detect_cryptdevices(
            [{"name": "sdb", "path": "/dev/sda", "type": "disk"}],
            only_active=True,
        )
        == []
    )
    # disks with mountpoint = null
    assert manage.LuksDevice.detect_cryptdevices(
        [
            {
                "name": "ceph-osd3-block",
                "path": "/dev/mapper/ceph-osd-3-block",
                "type": "crypt",
                "mountpoint": None,
                "children": [
                    {
                        "name": "vgosd3-ceph--osd3--block--crypted",
                        "path": "/dev/mapper/vgosd3-ceph--osd3--block--crypted",
                        "type": "lvm",
                        "mountpoint": None,
                        "children": [
                            {
                                "name": "sdd4",
                                "path": "/dev/sdd4",
                                "type": "part",
                                "mountpoint": None,
                                "children": [
                                    {
                                        "name": "sdd",
                                        "path": "/dev/sdd",
                                        "type": "disk",
                                        "mountpoint": None,
                                    }
                                ],
                            }
                        ],
                    }
                ],
            }
        ],
        only_active=True,
    ) == [
        manage.LuksDevice(
            luks_name="ceph-osd3-block",
            base_blockdev="/dev/mapper/vgosd3-ceph--osd3--block--crypted",
            base_blockdev_name="vgosd3-ceph--osd3--block--crypted",
            mountpoint=None,
        )
    ]


def test_detect_cryptdevices_all_volumes(mock_cryptsetup_isLuks):
    import json

    from fc.ceph.luks import manage

    # isLuks does not detect any additional devices: same as with `only_active=True`
    assert set(
        manage.LuksDevice.detect_cryptdevices(
            json.loads(LSBLK_JSON), only_active=False
        )
    ) == set(
        (
            manage.LuksDevice(
                base_blockdev="/dev/mapper/vgsys-ceph--mon--crypted",
                base_blockdev_name="vgsys-ceph--mon--crypted",
                luks_name="ceph-mon",
                mountpoint="/srv/ceph/mon/ceph-patty",
                header=None,
            ),
            manage.LuksDevice(
                base_blockdev="/dev/sdb1",
                base_blockdev_name="sdb1",
                luks_name="backy",
                mountpoint="/srv/backy",
                header=None,
            ),
            manage.LuksDevice(
                base_blockdev="/dev/mapper/vgsys-ceph--mgr--crypted",
                base_blockdev_name="vgsys-ceph--mgr--crypted",
                luks_name="ceph-mgr",
                mountpoint="/srv/ceph/mgr/ceph-patty",
                header=None,
            ),
        )
    )

    # additional device is detected
    mock_cryptsetup_isLuks.known_luks_devices.add(
        "/dev/mapper/vgosd--5-ceph--osd--5--wal--backup--crypted"
    )
    assert set(
        manage.LuksDevice.detect_cryptdevices(
            json.loads(LSBLK_JSON), only_active=False
        )
    ) == set(
        (
            manage.LuksDevice(
                base_blockdev="/dev/mapper/vgsys-ceph--mon--crypted",
                base_blockdev_name="vgsys-ceph--mon--crypted",
                luks_name="ceph-mon",
                mountpoint="/srv/ceph/mon/ceph-patty",
                header=None,
            ),
            manage.LuksDevice(
                base_blockdev="/dev/sdb1",
                base_blockdev_name="sdb1",
                luks_name="backy",
                mountpoint="/srv/backy",
                header=None,
            ),
            manage.LuksDevice(
                base_blockdev="/dev/mapper/vgsys-ceph--mgr--crypted",
                base_blockdev_name="vgsys-ceph--mgr--crypted",
                luks_name="ceph-mgr",
                mountpoint="/srv/ceph/mgr/ceph-patty",
                header=None,
            ),
            manage.LuksDevice(
                base_blockdev="/dev/mapper/vgosd--5-ceph--osd--5--wal--backup--crypted",
                base_blockdev_name="vgosd--5-ceph--osd--5--wal--backup--crypted",
                luks_name=None,
                mountpoint=None,
                header=None,
            ),
        )
    )

    # other errors of isLuks still bubble up
    mock_cryptsetup_isLuks.known_luks_devices = {}
    mock_cryptsetup_isLuks.illegal_devices.add(
        "/dev/mapper/vgosd--5-ceph--osd--5--wal--backup--crypted"
    )
    with pytest.raises(CalledProcessError):
        manage.LuksDevice.detect_cryptdevices(
            json.loads(LSBLK_JSON), only_active=False
        )


def test_keystore_rekey_argument_calls(mock_LUKSKeyStoreManager):
    keyman = mock_LUKSKeyStoreManager
    # testing with `only_active` is easier, no need to mock cryptsetup
    keyman.rekey(name_glob="*", only_active=True, header=None)
    keyman.rekey(
        name_glob="backy",
        only_active=True,
        slot="local",
        header="/srv/foo.luks",
    )
    keyman.rekey(
        name_glob="ceph*",
        only_active=True,
        slot="admin",
        header="/srv/foo.luks",
    )


@pytest.fixture
def inputs_mock(monkeypatch):
    """Returns a StringIO buffer that serves the lines served to `input()` calls.
    Add lines to this returned buffer like to any other TextIO object.
    """
    inputs = StringIO()
    monkeypatch.setattr("sys.stdin", inputs)
    return inputs


def persist_fingerprint(passphrase: bytes, path: pathlib.Path):
    with open(path / "admin.fprint", "wt") as fpfile:
        fpfile.write(hashlib.sha256(passphrase).hexdigest())


def test_keystore_admin_key_fingerprint_init(
    inputs_mock, tmpdir, capsys, patterns
):
    # feed data to `input()`
    inputs_mock.write(
        "\n".join(
            [
                # "LUKS admin key for this location: "
                "adminphrase-woops",
                # "Is '{e.current!s}' the correct new fingerprint?\nRetry otherwise."
                "n",
                # "LUKS admin key for this location: "
                "adminphrase",
                # "Is '{e.current!s}' the correct new fingerprint?\nRetry otherwise."
                "y",
            ]
        )
    )
    inputs_mock.seek(0)

    keystore = fc.ceph.luks.LUKSKeyStore()
    keystore.local_key_dir = tmpdir

    assert keystore.admin_key_for_input() == b"adminphrase"

    captured = capsys.readouterr()

    p = patterns.fpdialog
    p.optional("<empty-line>")
    p.continuous(
        dedent(
            """\
      No admin key fingerprint stored.
      Is 'a6c7cfad53bdcfeb670b3f8c7ac35df0aaffe2bbdd02c9f661835a596875f330' the correct new fingerprint?
      Retry otherwise. y/[n]: Retrying.
      No admin key fingerprint stored.
      Is '655ac90cabb7a9ea4e0f21a7e246400dc5fb062bad39ef9f2ecc55470e69c56e' the correct new fingerprint?
      Retry otherwise. y/[n]: Updating persisted fingerprint to """
        )
    )
    p.in_order(
        ".../admin.fprint\n"
        "Using admin key with matching fingerprint \n"
        "'655ac90cabb7a9ea4e0f21a7e246400dc5fb062bad39ef9f2ecc55470e69c56e'."
    )
    assert p == captured.out

    pe = patterns.fpdialog_getpass
    # If this was a multiline string, pre-commit would be eating the trailing spaces :\
    pe.optional("Warning: Password input may be echoed.")
    pe.in_order(
        "LUKS admin key for this location: \nLUKS admin key for this location: "
    )
    assert pe == captured.err

    # a 2nd call shall not require input again but return the cached phrase
    assert keystore.admin_key_for_input() == b"adminphrase"


def test_keystore_admin_key_fingerprint_existing(
    inputs_mock, tmpdir, capsys, patterns
):
    # initialise an existing keyphrase fingerprint
    persist_fingerprint(b"adminphrase", tmpdir)

    # feed data to `input()`
    inputs_mock.write("adminphrase\n")
    inputs_mock.seek(0)

    keystore = fc.ceph.luks.LUKSKeyStore()
    keystore.local_key_dir = tmpdir

    assert keystore.admin_key_for_input() == b"adminphrase"

    captured = capsys.readouterr()

    p = patterns.fpdialog
    p.optional("<empty-line>")
    p.in_order(
        "Using admin key with matching fingerprint \n"
        "'655ac90cabb7a9ea4e0f21a7e246400dc5fb062bad39ef9f2ecc55470e69c56e'."
    )
    assert p == captured.out

    pe = patterns.fpdialog_getpass
    pe.optional("Warning: Password input may be echoed.")
    pe.in_order("LUKS admin key for this location: ")
    assert pe == captured.err


def test_keystore_admin_key_fingerprint_existing_update(
    inputs_mock, tmpdir, capsys, patterns
):
    # initialise an existing keyphrase fingerprint
    persist_fingerprint(b"notadminphrase", tmpdir)

    # feed data to `input()`
    inputs_mock.write(
        "\n".join(
            [
                "adminphrase",
                # "Is '{e.current!s}' the correct new fingerprint?\nRetry otherwise."
                "y",
            ]
        )
    )
    inputs_mock.seek(0)

    keystore = fc.ceph.luks.LUKSKeyStore()
    keystore.local_key_dir = tmpdir

    assert keystore.admin_key_for_input() == b"adminphrase"

    captured = capsys.readouterr()

    p = patterns.fpdialog
    p.optional("<empty-line>")
    p.in_order(
        "Error: fingerprint mismatch:\n"
        "fingerprint for your entry: \n"
        "'655ac90cabb7a9ea4e0f21a7e246400dc5fb062bad39ef9f2ecc55470e69c56e'\n"
        "fingerprint stored locally: \n"
        "'10af63dfba16977d2b8533432fef5442c0b7f5ab7868597aaddcf440ced4756a'\n"
        "Is '655ac90cabb7a9ea4e0f21a7e246400dc5fb062bad39ef9f2ecc55470e69c56e' the correct new fingerprint?\n"
        "Retry otherwise. y/[n]: Updating persisted fingerprint to \n"
        ".../admin.fprint\n"
        "Using admin key with matching fingerprint \n"
        "'655ac90cabb7a9ea4e0f21a7e246400dc5fb062bad39ef9f2ecc55470e69c56e'."
    )
    assert p == captured.out
    pe = patterns.fpdialog_getpass
    pe.optional("Warning: Password input may be echoed.")
    pe.in_order("LUKS admin key for this location: ")
    assert pe == captured.err


def test_luks_fingerprint_command_invocation(
    inputs_mock, capsys, mock_LUKSKeyStoreManager, monkeypatch, tmp_path
):
    """smoke test for invocation via CLI arguments"""
    from fc.ceph.main import luks

    monkeypatch.setattr(
        "fc.ceph.main.CONFIG_FILE_PATH", tmp_path / "fc-ceph.conf"
    )

    with open(tmp_path / "fc-ceph.conf", "wt") as configfilemock:
        print(
            dedent(
                """\
        [default]
        path=/nix/store/qkb2vanjhgvhyn9c6d7nab97dp956cqn-ceph-14.2.22/bin:/nix/store/czcdjj2yjm3bdaamv2212ph11i446ldj-ceph-client-14.2.22/bin:/nix/store/qnwhmvhhs0kdd849zisbs0na0qr52qg4-xfsprogs-5.11.0-bin/bin:/nix/store/ljrwk0h6qifb661lc5mjz6vd712r05cd-lvm2-2.03.12-bin/bin:/nix/store/bfxkg8q43b5hbzhzmq6c5j2iqf6806a5-util-linux-2.36.2-bin/bin:/nix/store/6pzvibxjz7pdi1dgn1f2dav4b2fhdyga-systemd-247.6/bin:/nix/store/xa76ngikl4sqbk18f0zwhhxa9lfay3zq-gptfdisk-1.0.7/bin:/nix/store/y41s1vcn0irn9ahn9wh62yx2cygs7qjj-coreutils-8.32/bin:/nix/store/2w2v7y95ll8896kaybxhnaiv23rb7q9n-lz4-1.9.3-bin/bin:/nix/store/3j44b29gyrdkpvkj5cfn2cywgcx440ms-cryptsetup-2.3.5/bin
        release=nautilus
        """
            ),
            file=configfilemock,
        )

    # feed data to `input()`
    inputs_mock.write(
        "\n".join(
            [
                "foo",
                "foo",
                "foo",
            ]
        )
    )
    inputs_mock.seek(0)

    luks(["keystore", "fingerprint"])
    luks(["keystore", "fingerprint", "--no-confirm"])

    captured = capsys.readouterr()
    assert (
        captured.out
        == "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae\n"
        "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae\n"
    )


def test_luks_fingerprint_mismatch_retry(
    inputs_mock, capsys, mock_LUKSKeyStoreManager, patterns
):
    # feed data to `input()`
    inputs_mock.write(
        "\n".join(
            [
                "foo",
                "notfoo",
                "foo",
                "foo",
            ]
        )
    )
    inputs_mock.seek(0)
    mock_LUKSKeyStoreManager.fingerprint(confirm=True, verify=False)

    captured = capsys.readouterr()

    p = patterns.fpdialog
    p.optional("<empty-line>")
    p.in_order(
        "Mismatching passphrases entered, please retry.\n"
        "Error: fingerprint mismatch:\n"
        "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae"
    )

    pe = patterns.fpdialog_getpass
    pe.optional("Warning: Password input may be echoed.")
    pe.in_order(
        "Enter passphrase to fingerprint: \n"
        "Confirm passphrase again: \n"
        "Enter passphrase to fingerprint: \n"
        "Confirm passphrase again: "
    )
    assert pe == captured.err


def test_luks_fingerprint_verify(
    inputs_mock, capsys, tmpdir, mock_LUKSKeyStoreManager, patterns
):
    # feed data to `input()`
    inputs_mock.write(
        "\n".join(
            [
                "foo",
                "foo",
                "foo",
            ]
        )
    )
    inputs_mock.seek(0)

    # no fingerprint file
    assert mock_LUKSKeyStoreManager.fingerprint(confirm=False, verify=True) == 1

    # mismatching fingerprint file
    persist_fingerprint(b"notfoo", tmpdir)
    assert mock_LUKSKeyStoreManager.fingerprint(confirm=False, verify=True) == 1

    # matching fingerprint file
    persist_fingerprint(b"foo", tmpdir)
    assert mock_LUKSKeyStoreManager.fingerprint(confirm=False, verify=True) == 0

    captured = capsys.readouterr()

    p = patterns.fpdialog
    p.optional("<empty-line>")
    p.in_order(
        # 1st invocation
        "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae\n"
        "No admin key fingerprint stored.\n"
        # 2nd invocation
        "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae\n"
        "fingerprint for your entry: \n"
        "'2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae'\n"
        "fingerprint stored locally: \n"
        "'28b0289d1cceb110614259333e64a77ea39e87ec9add8af435c1271f8d2e9e13'\n"
        # 3rd invocation
        "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae"
    )
    pe = patterns.fpdialog_getpass
    pe.optional("Warning: Password input may be echoed.")
    pe.in_order(
        "Enter passphrase to fingerprint: \n"
        "Enter passphrase to fingerprint: \n"
        "Enter passphrase to fingerprint: "
    )
    assert pe == captured.err
