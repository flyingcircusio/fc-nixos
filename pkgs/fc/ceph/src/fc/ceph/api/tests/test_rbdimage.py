import freezegun

from ..rbdimage import RBDImage


class TestRBDImageTest(object):
    def test_from_dict(self):
        i = RBDImage.from_dict(
            {
                "format": 2,
                "image": "test05.root",
                "lock_type": "exclusive",
                "size": 5368709120,
            }
        )
        assert i == RBDImage("test05.root", 5368709120, 2, "exclusive")

    def test_from_dict_sets_defaults(self):
        i = RBDImage.from_dict({"image": "test05.root", "size": 5368709120})
        assert i == RBDImage("test05.root", 5368709120, 1, None)

    def test_size_gb(self):
        assert 5 == RBDImage("i", 5368709120, 2, None).size_gb

    def test_construct_with_defaults(self):
        i = RBDImage("test06.root", 10737418240)
        assert 1 == i.format
        assert i.lock_type is None
        assert "test06.root" == i.name

    def test_snapshot_name(self):
        i = RBDImage.from_dict(
            {"image": "foo", "size": 10000, "snapshot": "bar"}
        )
        assert "foo@bar" == i.name

    def test_protected(self):
        i = RBDImage.from_dict(
            {"image": "foo", "size": 10000, "protected": "true"}
        )
        assert i.protected

    @freezegun.freeze_time("2014-08-22")
    def test_image_without_snapshot_is_never_outdated(self):
        i = RBDImage.from_dict({"image": "foo", "size": 10240})
        assert not i.is_outdated_snapshot

    @freezegun.freeze_time("2014-08-23")
    def test_protected_image_is_never_outdated(self):
        i = RBDImage.from_dict(
            {
                "image": "foo",
                "size": 10240,
                "protected": "true",
                "snapshot": "test-keep-until-20140822",
            }
        )
        assert not i.is_outdated_snapshot

    @freezegun.freeze_time("2014-08-23")
    def test_locked_image_is_never_outdated(self):
        i = RBDImage.from_dict(
            {
                "image": "foo",
                "size": 10240,
                "lock_type": "exclusive",
                "snapshot": "test-keep-until-20140822",
            }
        )
        assert not i.is_outdated_snapshot

    @freezegun.freeze_time("2014-08-22")
    def test_snapshot_not_outdated(self):
        i = RBDImage.from_dict(
            {
                "image": "foo",
                "size": 10240,
                "snapshot": "test-keep-until-20140822",
            }
        )
        assert not i.is_outdated_snapshot

    @freezegun.freeze_time("2014-08-23")
    def test_snapshot_outdated_date(self):
        i = RBDImage.from_dict(
            {
                "image": "foo",
                "size": 10240,
                "snapshot": "test-keep-until-20140822",
            }
        )
        assert i.is_outdated_snapshot

    @freezegun.freeze_time("2014-08-23")
    def test_snapshot_outdated_time(self):
        i = RBDImage.from_dict(
            {
                "image": "foo",
                "size": 10240,
                "snapshot": "test-keep-until-20140822T105800",
            }
        )
        assert i.is_outdated_snapshot
