import json
from unittest.mock import Mock
from fc.ceph.logs import LogTasks
from pathlib import Path
import pytest

@pytest.fixture
def state_file(tmpdir) -> Path:
    state_file = tmpdir / "opslog_state.json"
    with state_file.open("w") as f:
        f.write(
            json.dumps(
                {
                    "last_processed_datetime": "2025-01-01T01",
                    "last_gced_day": "2024-12-28",
                }
            )
        )

    return state_file

@pytest.fixture
def enc_file(tmpdir) -> Path:
    enc_file = tmpdir / "enc.json"
    with enc_file.open("w") as f:
        f.write(
            json.dumps(
                {
                    "parameters": {
                        "location": "test"
                    }
                }
            )
        )

    return enc_file

@pytest.fixture
def enc_empty_services_file(tmpdir) -> Path:
    enc_file = tmpdir / "services.json"
    with enc_file.open("w") as f:
        f.write(
            json.dumps(
                []
            )
        )

    return enc_file


def test_account_s3_traffic_when_directory_is_unavailable(
    state_file, enc_file, enc_empty_services_file, monkeypatch
):
    class DirectoryCMMock:
        def lookup_networks(*args, **kwargs):
            return {}

        # Here, some failure happens and the directory isn't available anymore.
        def store_s3_traffic(*args, **kwargs):
             RuntimeError(
                "Network Exception!"
            )

    class DirectoryMock:
        def __init__(self, *args, **kwargs):
            pass
        

        def __enter__(self,):
            return DirectoryCMMock()
    
        def __exit__(self, *args, **kwargs):
            pass

    radosgw_admin_mock = Mock(
        side_effect=[
            # log list
            [
                "2025-02-01-01-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
            ],
            # log show
            {
                "bucket_id": "12345",
                "bucket_owner": "test",
                "bucket": "test",
                "log_entries": [
                    {
                        "remote_addr": "192.168.0.1",
                        "bucket": "test",
                        "bytes_sent": 23,
                        "bytes_received": 42,
                    },
                ],
                "log_sum": {"something": "in here"},
            },
        ]
    )

    monkeypatch.setattr("fc.ceph.util.run.json.radosgw_admin", radosgw_admin_mock)
    monkeypatch.setattr(
        "fc.ceph.util.directory.directory_connection", DirectoryMock
    )

    with pytest.raises(RuntimeError):
        LogTasks().account_s3_traffic(state_file, enc_file, enc_empty_services_file)

    assert json.load(state_file.open())["last_processed_datetime"] == "2025-01-01T01"
