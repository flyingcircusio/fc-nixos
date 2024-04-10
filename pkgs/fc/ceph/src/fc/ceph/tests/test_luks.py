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

LSBLK_PATTY_JSON = """
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
def mock_LUKSKeyStoreManager(monkeypatch):
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

    keyman._KEYSTORE = LUKSKeyStoreMock()
    keyman._do_rekey = do_nothing
    return keyman


def test_lsblk_to_cryptdevices():
    import json

    from fc.ceph.luks import manage

    assert set(
        manage.lsblk_to_cryptdevices(json.loads(LSBLK_PATTY_JSON))
    ) == set(
        (
            manage.LuksDevice(
                base_blockdev="/dev/mapper/vgsys-ceph--mon--crypted",
                name="ceph-mon",
                mountpoint="/srv/ceph/mon/ceph-patty",
            ),
            manage.LuksDevice(
                base_blockdev="/dev/sdb1",
                name="backy",
                mountpoint="/srv/backy",
            ),
            manage.LuksDevice(
                base_blockdev="/dev/mapper/vgsys-ceph--mgr--crypted",
                name="ceph-mgr",
                mountpoint="/srv/ceph/mgr/ceph-patty",
            ),
        )
    )
    assert manage.lsblk_to_cryptdevices([]) == []
    # disks, but no crypt and no children
    assert (
        manage.lsblk_to_cryptdevices(
            [{"name": "sdb", "path": "/dev/sda", "type": "disk"}]
        )
        == []
    )
    # disks with mountpoint = null
    assert manage.lsblk_to_cryptdevices(
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
        ]
    ) == [
        manage.LuksDevice(
            name="ceph-osd3-block",
            base_blockdev="/dev/mapper/vgosd3-ceph--osd3--block--crypted",
            mountpoint=None,
        )
    ]


def test_keystore_rekey_argument_calls(mock_LUKSKeyStoreManager):
    keyman = mock_LUKSKeyStoreManager
    keyman.rekey(name_glob="*", header=None)
    keyman.rekey(name_glob="backy", slot="local", header="/srv/foo.luks")
    keyman.rekey(name_glob="ceph*", slot="admin", header="/srv/foo.luks")
