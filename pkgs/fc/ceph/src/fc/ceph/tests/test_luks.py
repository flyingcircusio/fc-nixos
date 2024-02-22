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
    keyman = fc.ceph.luks.manage.LUKSKeyStoreManager()

    keyman._KEYSTORE = LUKSKeyStoreMock()
    keyman._do_rekey = do_nothing
    return keyman


def test_keystore_rekey_argument_errors(mock_LUKSKeyStoreManager):
    keyman = mock_LUKSKeyStoreManager
    with pytest.raises(ValueError):
        keyman.rekey(lvs=None, device=None, header=None)
    with pytest.raises(ValueError):
        keyman.rekey(lvs="*", device="/dev/foo", header="/srv/foo.luks")
    with pytest.raises(ValueError):
        keyman.rekey(
            lvs="*", device=None, slot="whatever", header="/srv/foo.luks"
        )


def test_keystore_rekey_argument_calls(mock_LUKSKeyStoreManager):
    keyman = mock_LUKSKeyStoreManager
    keyman.rekey(lvs="*", device=None, header=None)
    keyman.rekey(lvs="*", slot="local", header="/srv/foo.luks", device=None)
    keyman.rekey(lvs="*", slot="admin", header="/srv/foo.luks", device=None)
    keyman.rekey(device="/dev/foo", header="/srv/foo.luks", lvs=None)
