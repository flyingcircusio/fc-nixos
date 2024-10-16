from unittest.mock import MagicMock, Mock, call

import pytest


@pytest.fixture
def example_directory_user_report():
    return {
        "services:sometest": {
            "location": "rzob",
            "storage_resource_group": "services",
            "display_name": "test test",
            "access_key": "dnDlid0jyRs1sK9vEOGV",
            "secret_key": "VqBfxCqupucBSjo7ksDcf4K6vhgsIdGKnL0ielLi",
            "deletion": {"deadline": "", "stages": ["soft"]},
        }
    }


@pytest.fixture
def example_radosgw_info_full():
    return {
        "user_id": "foo",
        "display_name": "something",
        "email": "",
        "suspended": 0,
        "max_buckets": 1000,
        "subusers": [],
        "keys": [
            {
                "user": "foo",
                "access_key": "03KAF2L1WU7PHIH0Hlol",
                "secret_key": "yGyKB4sAJ3qdMWp3n2mR6tx61MozXlVVaCrefMxD",
            }
        ],
        "swift_keys": [],
        "caps": [],
        "op_mask": "read, write, delete",
        "default_placement": "",
        "default_storage_class": "",
        "placement_tags": [],
        "bucket_quota": {
            "enabled": False,
            "check_on_raw": False,
            "max_size": -1,
            "max_size_kb": 0,
            "max_objects": -1,
        },
        "user_quota": {
            "enabled": False,
            "check_on_raw": False,
            "max_size": -1,
            "max_size_kb": 0,
            "max_objects": -1,
        },
        "temp_url_keys": [],
        "type": "rgw",
        "mfa_ids": [],
    }


# TODO: directory ring api mock (xmlrpc server)


@pytest.fixture
def radosgw_admin_calls(monkeypatch):
    mock_obj = Mock()
    monkeypatch.setattr("fc.util.runners.run.radosgw_admin", mock_obj)
    return mock_obj


@pytest.fixture
def radosgw_admin_json_calls(monkeypatch):
    mock_obj = Mock()
    monkeypatch.setattr("fc.util.runners.run.json.radosgw_admin", mock_obj)
    return mock_obj


@pytest.fixture
def radosgwUserManager_init_no_sideeffects():
    from fc.manage.s3users import RadosgwUserManager

    RadosgwUserManager._get_local_user_report = lambda _: {}
    RadosgwUserManager._get_directory_user_report = lambda _: {}
    return RadosgwUserManager


def test_S3User_instance():
    from fc.manage.s3users import DirectoryS3User, S3User

    S3User(
        "services:grafana",
        "Grafana FCIO",
        "asdfghjk",
        "mpyf096bb3zT0fg5T6PR0ArNxCegKZ3hz5p11UAQ",
    )
    DirectoryS3User(
        "services:grafana",
        "Grafana FCIO",
        "asdfghjk",
        "mpyf096bb3zT0fg5T6PR0ArNxCegKZ3hz5p11UAQ",
        ["soft", "hard"],
    )


def test_S3User_from_radosgw_json(example_radosgw_info_full):
    from fc.manage.s3users import S3User

    user = S3User.from_radosgw(example_radosgw_info_full)
    assert user == S3User(
        uid="foo",
        display_name="something",
        access_key="03KAF2L1WU7PHIH0Hlol",
        secret_key="yGyKB4sAJ3qdMWp3n2mR6tx61MozXlVVaCrefMxD",
    )


def test_S3User_from_radosgw_json_ignores_further_keys(
    example_radosgw_info_full,
):
    from fc.manage.s3users import S3User

    example_radosgw_info_full["keys"].append(
        {
            "user": "foo",
            "access_key": "asdfghjk",
            "secret_key": "thisisignoredanyways",
        }
    )
    user = S3User.from_radosgw(example_radosgw_info_full)
    assert user == S3User(
        uid="foo",
        display_name="something",
        access_key="03KAF2L1WU7PHIH0Hlol",
        secret_key="yGyKB4sAJ3qdMWp3n2mR6tx61MozXlVVaCrefMxD",
    )


def test_DirectoryS3User_from_directory(example_directory_user_report):
    from fc.manage.s3users import DirectoryS3User

    uid, user_dict = example_directory_user_report.popitem()
    user = DirectoryS3User.from_directory(uid, user_dict)

    assert user == DirectoryS3User(
        uid="services:sometest",
        display_name="test test",
        access_key="dnDlid0jyRs1sK9vEOGV",
        secret_key="VqBfxCqupucBSjo7ksDcf4K6vhgsIdGKnL0ielLi",
        deletion_stages=["soft"],
    )


def test_ensure_exists_creates_user(
    radosgw_admin_calls, radosgw_admin_json_calls
):
    from fc.manage.s3users import DirectoryS3User, S3User

    user = DirectoryS3User(
        uid="services:sometest",
        display_name="test test",
        access_key="dnDlid0jyRs1sK9vEOGV",
        secret_key="VqBfxCqupucBSjo7ksDcf4K6vhgsIdGKnL0ielLi",
        deletion_stages=[],
    )

    local_users = {}
    user.ensure(local_users)

    assert "services:sometest" in local_users

    assert radosgw_admin_calls.call_args_list == []
    assert radosgw_admin_json_calls.call_args_list == [
        call(
            # fmt: off
            "user", "create",
            "--uid", "services:sometest",
            "--display-name", "test test",
            "--access-key", "dnDlid0jyRs1sK9vEOGV",
            # fmt: on
        ),
        call(
            # fmt: off
            "user", "modify",
            "--uid", "services:sometest",
            "--display-name", "test test",
            "--access-key", "dnDlid0jyRs1sK9vEOGV",
            "--secret-key", "VqBfxCqupucBSjo7ksDcf4K6vhgsIdGKnL0ielLi",
            # fmt: on
        ),
    ]


def test_ensure_exists_creates_user_no_secret_provided(
    radosgw_admin_calls, radosgw_admin_json_calls, caplog
):
    import logging

    from fc.manage.s3users import DirectoryS3User, S3User

    caplog.set_level(logging.INFO)

    user = DirectoryS3User(
        uid="services:sometest",
        display_name="test test",
        access_key="dnDlid0jyRs1sK9vEOGV",
        secret_key=None,
        deletion_stages=[],
    )

    local_users = {}
    user.ensure(local_users)

    assert "services:sometest" in local_users

    assert radosgw_admin_calls.call_args_list == []
    assert radosgw_admin_json_calls.call_args_list == [
        call(
            # fmt: off
            "user", "create",
            "--uid", "services:sometest",
            "--display-name", "test test",
            "--access-key", "dnDlid0jyRs1sK9vEOGV",
            # fmt: on
        ),
        call(
            # fmt: off
            "user", "modify",
            "--uid", "services:sometest",
            "--display-name", "test test",
            # fmt: on
        ),
    ]

    assert "no secret key provided" in caplog.text


# test update existing


def test_ensure_updates_users(radosgw_admin_calls, radosgw_admin_json_calls):
    from fc.manage.s3users import DirectoryS3User, S3User

    existing_user = S3User(
        uid="services:sometest",
        display_name="test test",
        access_key="dnDlid0jyRs1sK9vEOGV",
        secret_key="VqBfxCqupucBSjo7ksDcf4K6vhgsIdGKnL0ielLi",
    )
    local_users = {existing_user.uid: existing_user}
    user = DirectoryS3User(
        uid="services:sometest",
        display_name="test test",
        access_key="dnDlid0jyRs1sK9vEOGV",
        secret_key="VqBfxCqupucBSjo7ksDcf4K6vhgsIdGKnL0ielLi",
        deletion_stages=[],
    )

    user.ensure(local_users)

    assert "services:sometest" in local_users
    assert local_users["services:sometest"] == user

    assert radosgw_admin_calls.call_args_list == []
    assert radosgw_admin_json_calls.call_args_list == [
        # idempotent: modify still issued for equal user properties
        call(
            # fmt: off
            "user", "modify",
            "--uid", "services:sometest",
            "--display-name", "test test",
            "--access-key", "dnDlid0jyRs1sK9vEOGV",
            "--secret-key", "VqBfxCqupucBSjo7ksDcf4K6vhgsIdGKnL0ielLi",
            # fmt: on
        ),
    ]

    radosgw_admin_json_calls.reset_mock()

    # modified secret
    user.access_key = "asdf"
    user.secret_key = "hjkl"

    user.ensure(local_users)

    assert "services:sometest" in local_users
    assert local_users["services:sometest"].access_key == "asdf"
    assert local_users["services:sometest"].secret_key == "hjkl"

    assert radosgw_admin_calls.call_args_list == []
    assert radosgw_admin_json_calls.call_args_list == [
        call(
            # fmt: off
            "user", "modify",
            "--uid", "services:sometest",
            "--display-name", "test test",
            "--access-key", "asdf",
            "--secret-key", "hjkl"
            # fmt: on
        ),
    ]

    radosgw_admin_json_calls.reset_mock()

    # modified name, no secret

    user.secret_key = None
    user.display_name = "changed test"

    user.ensure(local_users)

    assert "services:sometest" in local_users
    assert local_users["services:sometest"].access_key == "asdf"
    assert local_users["services:sometest"].secret_key == None

    assert radosgw_admin_calls.call_args_list == []
    assert radosgw_admin_json_calls.call_args_list == [
        call(
            # fmt: off
            "user", "modify",
            "--uid", "services:sometest",
            "--display-name", "changed test",
            # fmt: on
        ),
    ]


# test still add with soft

# test no add with hard
