import json
import logging
import subprocess
from subprocess import CalledProcessError
from unittest.mock import Mock, call

import pytest
from fc.manage.s3users import (
    DirectoryState,
    RGWState,
    User,
    UserManager,
    accounting,
)

# TODO: directory ring api mock (xmlrpc server)


@pytest.fixture
def subprocess_run(monkeypatch):
    mock_obj = Mock()
    monkeypatch.setattr("subprocess.run", mock_obj)
    return mock_obj


def test_object_instances_trivial(subprocess_run):
    user = User("test")
    assert user.uid == "test"
    assert isinstance(user.rgw, RGWState)
    assert isinstance(user.directory, DirectoryState)

    assert not user.should_exist
    assert not user.should_be_deleted

    subprocess_run().stdout = json.dumps(
        {
            "display_name": "Test User",
            "keys": [
                {
                    "access_key": "12345",
                    "secret_key": "abcde",
                }
            ],
        }
    )
    user.rgw.update()
    assert user.rgw.display_name == "Test User"
    assert user.rgw.key_count == 1
    assert user.rgw.access_key == "12345"
    assert user.rgw.secret_key == "abcde"

    user.directory.update(
        {
            "display_name": "Test User",
            "access_key": "12345",
            "secret_key": "abcde",
            "deletion": {"stages": ["foo"]},
        }
    )
    assert user.directory.display_name == "Test User"
    assert user.directory.access_key == "12345"
    assert user.directory.secret_key == "abcde"
    assert user.directory.deletion_stages == ["foo"]
    assert user.directory.key_count == 1

    assert list(user.compare_states()) == []
    assert user.validate()


def test_rgw_state_ignores_additional_keys(
    subprocess_run,
):
    user = User("test")

    subprocess_run().stdout = json.dumps(
        {
            "display_name": "Test User",
            "keys": [
                {
                    "access_key": "12345",
                    "secret_key": "abcde",
                },
                {
                    "access_key": "67890",
                    "secret_key": "fghij",
                },
            ],
        }
    )
    user.rgw.update()

    assert user.rgw.key_count == 2
    assert user.rgw.access_key == "12345"
    assert user.rgw.secret_key == "abcde"


def test_ensure_exists_creates_user(subprocess_run, caplog, capfd):
    caplog.set_level(logging.INFO)

    user = User("services:sometest")
    user.directory.update(
        {
            "display_name": "test test",
            "access_key": "dnDlid0jyRs1sK9vEOGV",
            "secret_key": "directory-provided-secret-key",
            "deletion": {"stages": []},
        }
    )

    subprocess_run.side_effect = [
        Mock(stdout=""),
        Mock(stdout=""),
        Mock(
            stdout=json.dumps(
                {
                    "display_name": "test test",
                    "keys": [
                        {
                            "access_key": "dnDlid0jyRs1sK9vEOGV",
                            "secret_key": "directory-provided-secret-key",
                        },
                    ],
                }
            )
        ),
    ]

    assert not user.rgw.exists
    user.ensure()
    assert user.rgw.exists
    assert user.rgw.display_name == "test test"
    assert user.rgw.access_key == "dnDlid0jyRs1sK9vEOGV"
    assert user.rgw.secret_key == "directory-provided-secret-key"
    assert user.rgw.key_count == 1

    assert subprocess_run.call_args_list == [
        call(
            [
                "radosgw-admin", "user", "create",
                "--uid", "services:sometest",
                "--display-name", "test test",
                "--access-key", "dnDlid0jyRs1sK9vEOGV",
                "--gen-secret"
            ],
            check=True, stdout=-1, stderr=-1,
        ),
        call(
            [
                "radosgw-admin", "user", "modify",
                "--uid", "services:sometest",
                "--display-name", "test test",
                "--access-key", "dnDlid0jyRs1sK9vEOGV",
                "--secret-key", "directory-provided-secret-key",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
        call(
            [
                "radosgw-admin", "--format", "json",
                "user", "info",
                "--uid", "services:sometest",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
    ]  # fmt: skip

    captured = capfd.readouterr()
    assert "directory-provided-secret-key" not in caplog.text
    assert "directory-provided-secret-key" not in captured.out
    assert "directory-provided-secret-key" not in captured.err
    assert "<REDACTED>" in captured.out


def test_ensure_exists_creates_user_no_secret_provided(subprocess_run, caplog):
    import logging

    caplog.set_level(logging.INFO)

    user = User("services:sometest")
    user.directory.update(
        {
            "display_name": "test test",
            "access_key": "dnDlid0jyRs1sK9vEOGV",
            "secret_key": None,
            "deletion": {"stages": []},
        }
    )

    subprocess_run.side_effect = [
        Mock(stdout=""),
        Mock(stdout=""),
        Mock(
            stdout=json.dumps(
                {
                    "display_name": "test test",
                    "keys": [
                        {
                            "access_key": "dnDlid0jyRs1sK9vEOGV",
                            "secret_key": "randomsecretkey",
                        },
                    ],
                }
            )
        ),
    ]

    assert not user.rgw.exists
    user.ensure()
    assert user.rgw.exists
    assert user.rgw.display_name == "test test"
    assert user.rgw.access_key == "dnDlid0jyRs1sK9vEOGV"
    assert user.rgw.secret_key == "randomsecretkey"
    assert user.rgw.key_count == 1

    assert subprocess_run.call_args_list == [
        call(
            [
                "radosgw-admin", "user", "create",
                "--uid", "services:sometest",
                "--display-name", "test test",
                "--access-key", "dnDlid0jyRs1sK9vEOGV",
                "--gen-secret"
            ],
            check=True, stdout=-1, stderr=-1,
        ),
        call(
            [
                "radosgw-admin", "user", "modify",
                "--uid", "services:sometest",
                "--display-name", "test test",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
        call(
            [
                "radosgw-admin", "--format", "json",
                "user", "info",
                "--uid", "services:sometest",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
    ]  # fmt: skip

    assert "no secret key provided" in caplog.text


def test_ensure_updates_users(subprocess_run):
    user = User("services:sometest")
    user.directory.update(
        {
            "display_name": "a new display name",
            "access_key": "the access key",
            "secret_key": "a new secret key",
            "deletion": {"stages": []},
        }
    )

    subprocess_run.side_effect = [
        Mock(
            stdout=json.dumps(
                {
                    "display_name": "old display name",
                    "keys": [
                        {
                            "access_key": "the access key",
                            "secret_key": "old secret key",
                        },
                    ],
                }
            )
        ),
        Mock(stdout=""),
        Mock(
            stdout=json.dumps(
                {
                    "display_name": "new display name",
                    "keys": [
                        {
                            "access_key": "the access key",
                            "secret_key": "new secret key",
                        },
                    ],
                }
            )
        ),
    ]

    user.rgw.update()
    assert user.rgw.exists
    assert user.rgw.display_name == "old display name"
    assert user.rgw.access_key == "the access key"
    assert user.rgw.secret_key == "old secret key"

    user.ensure()

    assert user.rgw.exists
    assert user.rgw.display_name == "new display name"
    assert user.rgw.access_key == "the access key"
    assert user.rgw.secret_key == "new secret key"
    assert user.rgw.key_count == 1

    assert subprocess_run.call_args_list == [
        call(
            [
                "radosgw-admin", "--format", "json",
                "user", "info",
                "--uid", "services:sometest",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
        call(
            [
                "radosgw-admin", "user", "modify",
                "--uid", "services:sometest",
                "--display-name", "a new display name",
                "--access-key", "the access key",
                "--secret-key", "a new secret key",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
        call(
            [
                "radosgw-admin", "--format", "json",
                "user", "info",
                "--uid", "services:sometest",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
    ]  # fmt: skip


def test_validation(caplog):
    user = User("test")

    user.directory.exists = True
    user.rgw.exists = False

    assert not user.validate()
    assert list(user.compare_states()) == [
        "- Differing key_count: RGW has 0, directory has 1"
    ]

    assert (
        "User data mismatch for test:\n- not found in local users\n"
        in caplog.text
    )

    user.directory.exists = False
    user.rgw.exists = True

    assert not user.validate()
    assert (
        "- is not known in the directory but exists (unmanaged) in RGW"
        in caplog.text
    )

    user.directory.exists = True
    user.rgw.exists = True

    user.directory.display_name = "directory"
    user.directory.access_key = "directory"
    user.directory.secret_key = "directory"

    user.rgw.display_name = "rgw"
    user.rgw.access_key = "rgw"
    user.rgw.secret_key = "rgw"

    assert list(user.compare_states()) == [
        "- Differing display_name: RGW has 'rgw', directory has 'directory'",
        "- Differing access_key: RGW has 'rgw', directory has 'directory'",
        "- Differing key_count: RGW has 0, directory has 1",
    ]
    assert not user.validate()

    user.directory.exists = False
    user.rgw.exists = False
    assert user.validate()


def test_users_pending_soft_deletion_still_added(subprocess_run, caplog):
    user = User("services:sometest")
    user.directory.update(
        {
            "display_name": "test test",
            "access_key": "dnDlid0jyRs1sK9vEOGV",
            "secret_key": None,
            "deletion": {"stages": ["soft"]},
        }
    )

    subprocess_run.side_effect = [
        Mock(stdout=""),
        Mock(stdout=""),
        Mock(
            stdout=json.dumps(
                {
                    "display_name": "test test",
                    "keys": [
                        {
                            "access_key": "dnDlid0jyRs1sK9vEOGV",
                            "secret_key": "random-key",
                        },
                    ],
                }
            )
        ),
        Mock(
            stdout=json.dumps(
                {
                    "display_name": "test test",
                    "keys": [
                        {
                            "access_key": "some-old-key",
                            "secret_key": "...",
                        },
                        {
                            "access_key": "some-other-old-key",
                            "secret_key": "...",
                        },
                    ],
                }
            )
        ),
        Mock(stdout=""),
        Mock(stdout=""),
        Mock(
            stdout=json.dumps(
                {
                    "display_name": "test test",
                    "keys": [],
                }
            )
        ),
    ]

    assert not user.rgw.exists
    user.ensure()
    assert user.rgw.exists
    assert user.rgw.display_name == "test test"
    assert user.rgw.access_key == None
    assert user.rgw.secret_key == None
    assert user.rgw.key_count == 0

    assert subprocess_run.call_args_list == [
        call(
            [
                "radosgw-admin", "user", "create",
                "--uid", "services:sometest",
                "--display-name", "test test",
                "--access-key", "dnDlid0jyRs1sK9vEOGV",
                "--gen-secret"
            ],
            check=True, stdout=-1, stderr=-1,
        ),
        call(
            [
                "radosgw-admin", "user", "modify",
                "--uid", "services:sometest",
                "--display-name", "test test",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
        call(
            [
                "radosgw-admin", "--format", "json",
                "user", "info",
                "--uid", "services:sometest",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
        call(
            [
                "radosgw-admin", "--format", "json",
                "user", "info",
                "--uid", "services:sometest",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
        call(
            [
                "radosgw-admin", "key", "rm",
                "--access-key", "some-old-key",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
        call(
            [
                "radosgw-admin", "key", "rm",
                "--access-key", "some-other-old-key",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
        call(
            [
                "radosgw-admin", "--format", "json",
                "user", "info",
                "--uid", "services:sometest",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
    ]  # fmt: skip

    assert user.validate()


def test_ensure_does_not_recreate_hard_deleted_users(subprocess_run):
    user = User("services:sometest")
    user.directory.update(
        {
            "display_name": "test test",
            "access_key": "dnDlid0jyRs1sK9vEOGV",
            "secret_key": None,
            "deletion": {"stages": ["soft", "hard"]},
        }
    )

    subprocess_run.side_effect = []

    assert not user.rgw.exists
    user.ensure()
    assert not user.rgw.exists
    assert user.rgw.display_name is None
    assert user.rgw.access_key is None
    assert user.rgw.secret_key is None
    assert user.rgw.key_count == 0

    assert subprocess_run.call_args_list == []

    assert user.validate()
    assert list(user.compare_states()) == [
        "- Differing display_name: RGW has None, directory has 'test test'",
        "- Differing access_key: RGW has None, directory has 'dnDlid0jyRs1sK9vEOGV'",
        "- Differing key_count: RGW has 0, directory has 1",
    ]


def test_ensure_hard_state_deletes_users(subprocess_run):
    user = User("services:sometest")
    user.directory.update(
        {
            "display_name": "test test",
            "access_key": "dnDlid0jyRs1sK9vEOGV",
            "secret_key": "asdf",
            "deletion": {"stages": []},
        }
    )

    subprocess_run.side_effect = [
        Mock(stdout=""),
        Mock(stdout=""),
        Mock(
            stdout=json.dumps(
                {
                    "display_name": "test test",
                    "keys": [
                        {
                            "access_key": "dnDlid0jyRs1sK9vEOGV",
                            "secret_key": "asdf",
                        },
                    ],
                }
            )
        ),
    ]

    # Create the user
    user.ensure()

    assert user.rgw.exists
    assert user.rgw.display_name == "test test"
    assert user.rgw.key_count == 1
    assert user.rgw.access_key == "dnDlid0jyRs1sK9vEOGV"
    assert user.rgw.secret_key == "asdf"

    subprocess_run.reset_mock()

    assert subprocess_run.call_args_list == []

    user.directory.update(
        {
            "display_name": "test test",
            "access_key": "dnDlid0jyRs1sK9vEOGV",
            "secret_key": "asdf",
            "deletion": {"stages": ["soft", "hard"]},
        }
    )

    subprocess_run.side_effect = [
        Mock(stdout=""),
        subprocess.CalledProcessError(cmd="", returncode=22, output=b"", stderr=b"could not fetch user info: no user info saved")
    ]

    user.ensure()

    assert not user.rgw.exists
    assert user.rgw.display_name is None
    assert user.rgw.access_key is None
    assert user.rgw.secret_key is None
    assert user.rgw.key_count == 0

    assert subprocess_run.call_args_list == [
        call(
            [
                "radosgw-admin", "user", "rm",
                "--uid", "services:sometest",
                "--purge-data", "--purge-keys",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
        call(
            [
                "radosgw-admin", "--format", "json",
                "user", "info",
                "--uid", "services:sometest",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
    ]  # fmt: skip

    assert user.validate()
    assert list(user.compare_states()) == [
        "- Differing display_name: RGW has None, directory has 'test test'",
        "- Differing access_key: RGW has None, directory has 'dnDlid0jyRs1sK9vEOGV'",
        "- Differing key_count: RGW has 0, directory has 1",
    ]


def test_accounting(subprocess_run):
    directory = Mock()

    subprocess_run.side_effect = [
        Mock(stdout=json.dumps(["services:user1"])),
        Mock(stdout=json.dumps({"stats": {"total_bytes": 1000}})),
    ]

    accounting("test-location", directory)

    assert directory.store_s3.call_args_list == [
        call("test-location", {"services:user1": "1000"})
    ]


def test_user_manager(subprocess_run, caplog):
    caplog.set_level(logging.INFO)

    directory = Mock()
    directory.list_s3_users.return_value = {
        "services:sometest": {
            "location": "test",
            "storage_resource_group": "services",
            "display_name": "test test",
            "access_key": "dnDlid0jyRs1sK9vEOGV",
            "secret_key": "VqBfxCqupucBSjo7ksDcf4K6vhgsIdGKnL0ielLi",
            "deletion": {"deadline": "", "stages": []},
        }
    }

    subprocess_run.side_effect = [
        Mock(stdout=json.dumps(["services:user1"])),
        Mock(
            stdout=json.dumps(
                {
                    "display_name": "user 1",
                    "keys": [
                        {
                            "access_key": "some-old-key",
                            "secret_key": "...",
                        },
                        {
                            "access_key": "some-other-old-key",
                            "secret_key": "...",
                        },
                    ],
                }
            )
        ),
        Mock(stdout=""),  # user create
        Mock(stdout=""),  # user update
        Mock(
            stdout=json.dumps(
                {
                    "display_name": "test test",
                    "keys": [
                        {
                            "access_key": "dnDlid0jyRs1sK9vEOGV",
                            "secret_key": "VqBfxCqupucBSjo7ksDcf4K6vhgsIdGKnL0ielLi",
                        },
                    ],
                }
            )
        ),
    ]

    manager = UserManager(directory, "test", "services")
    manager.sync_users()

    assert directory.list_s3_users.call_args_list == [call()]
    assert directory.update_s3_users.call_args_list == [
        call(
            {
                "services:sometest": {
                    "display_name": "test test",
                    "access_key": "dnDlid0jyRs1sK9vEOGV",
                    "location": "test",
                    "storage_resource_group": "services",
                    "secret_key": None,
                },
                "services:user1": {
                    "display_name": "user 1",
                    "access_key": "some-old-key",
                    "location": "test",
                    "storage_resource_group": "services",
                    "secret_key": None,
                },
            }
        )
    ]

    assert (
        " User data mismatch for services:user1:\n- is not known in the directory but exists (unmanaged) in RGW"
        in caplog.text
    )


def test_usermanager_blocks_users_from_foreign_location_or_resource_group():
    directory = Mock()
    directory.list_s3_users.return_value = {
        "services:sometest": {
            "location": "wrong-location",
            "storage_resource_group": "correct-resource-group",
            "display_name": "test test",
            "access_key": "dnDlid0jyRs1sK9vEOGV",
            "secret_key": "VqBfxCqupucBSjo7ksDcf4K6vhgsIdGKnL0ielLi",
            "deletion": {"deadline": "", "stages": []},
        }
    }

    with pytest.raises(AssertionError) as e:
        UserManager(directory, "correct-location", "correct-resource-group")
    assert (
        e.value.args[0]
        == "Encountered user from unexpected location: wrong-location"
    )

    directory.list_s3_users.return_value = {
        "services:sometest": {
            "location": "correct-location",
            "storage_resource_group": "wrong-resource-group",
            "display_name": "test test",
            "access_key": "dnDlid0jyRs1sK9vEOGV",
            "secret_key": "VqBfxCqupucBSjo7ksDcf4K6vhgsIdGKnL0ielLi",
            "deletion": {"deadline": "", "stages": []},
        }
    }

    with pytest.raises(AssertionError) as e:
        UserManager(directory, "correct-location", "correct-resource-group")
    assert (
        e.value.args[0]
        == "Encountered user from unexpected storage resource group: wrong-resource-group"
    )

def test_rgw_user_unknown_error_info_doesnt_create_user_again(subprocess_run, caplog):
    caplog.set_level(logging.INFO)

    directory = Mock()
    directory.list_s3_users.return_value = {
        "services:sometest": {
            "location": "test",
            "storage_resource_group": "services",
            "display_name": "test test",
            "access_key": "dnDlid0jyRs1sK9vEOGV",
            "secret_key": "",
            "deletion": {"deadline": "", "stages": []},
        }
    }

    subprocess_run.side_effect = [
        Mock(stdout=json.dumps(["services:sometest"])),
        CalledProcessError(returncode=1, cmd="", output=b"", stderr=b"uh, i'm a weird error")
    ]

    with pytest.raises(CalledProcessError):
        UserManager(directory, "test", "services")

    assert subprocess_run.call_args_list == [
        call(
            [
                "radosgw-admin", "--format", "json",
                "user", "list",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
        call(
            [
                "radosgw-admin", "--format", "json",
                "user", "info", "--uid", "services:sometest",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
    ]

    assert directory.list_s3_users.call_args_list == [call()]
    assert directory.update_s3_users.call_args_list == []


def test_rgw_user_unknown_error_list_doesnt_create_user_again(subprocess_run, caplog):
    caplog.set_level(logging.INFO)

    directory = Mock()
    directory.list_s3_users.return_value = {
        "services:sometest": {
            "location": "test",
            "storage_resource_group": "services",
            "display_name": "test test",
            "access_key": "dnDlid0jyRs1sK9vEOGV",
            "secret_key": "",
            "deletion": {"deadline": "", "stages": []},
        }
    }

    subprocess_run.side_effect = [
        CalledProcessError(returncode=1, cmd="", output=b"", stderr=b"uh, i'm a weird list error")
    ]

    with pytest.raises(CalledProcessError):
        UserManager(directory, "test", "services")

    assert subprocess_run.call_args_list == [
        call(
            [
                "radosgw-admin", "--format", "json",
                "user", "list",
            ],
            check=True, stdout=-1, stderr=-1,
        ),
    ]

    assert directory.list_s3_users.call_args_list == [call()]
    assert directory.update_s3_users.call_args_list == []
