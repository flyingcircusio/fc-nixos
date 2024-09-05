import pytest

# TODO validate data format by calling dev deployment’s direcory API
DIRECTOR_API_ENVIRONMENTS = [
    {
        "name": "default",
        "url": "p:default",
        "release_metadata": None,
        "title": "[Puppet] default",
        "environment_class": "Puppet",
    },
    {
        "name": "dev-os",
        "url": "file:///home/os/fc-nixos/channels/",
        "release_metadata": {
            "channel_url": "file:///home/os/fc-nixos/channels/",
            "changelog_url": None,
            "devhost_image_url": None,
            "devhost_image_hash": None,
            "image_url": None,
            "image_hash": None,
            "release_name": "dev_release_1",
            "rolling_channel": False,
        },
        "title": "[NixOS] dev-os",
        "environment_class": "NixOS",
    },
    {
        "name": "fc-23.05-production",
        "url": "https://hydra.flyingcircus.io/build/456547/download/1/nixexprs.tar.xz",
        "release_metadata": {
            "channel_url": "https://hydra.flyingcircus.io/build/456547/download/1/nixexprs.tar.xz",
            "changelog_url": "https://doc.flyingcircus.io/platform/changes/2024/r021.html",
            "devhost_image_url": "https://hydra.flyingcircus.io/build/450912/download/1",
            "devhost_image_hash": "sha256-ODE1NTA0MmM0Mjk5ODJjN2VkODdhMjJmYjA2ZDM1NDUwZDhhYTUyYjVjYTQwYjBmMjBiZTU0ZDllYmRmYWY1OA==",
            "image_url": "https://hydra.flyingcircus.io/build/450936/download/1",
            "image_hash": "sha256-ZjBiODZlZTBkYzFlM2Y4Y2M0MTRiNzIzNWNhZjJmZjk1YmIxYjczNmY5OTE3ZjZmODViYjM2Yzg0NDVjOTU0Yg==",
            "release_name": "2024_021",
            "rolling_channel": False,
        },
        "title": "[NixOS] fc-23.05-production",
        "environment_class": "NixOS",
    },
    {
        "name": "fc-23.05-staging",
        "url": "https://hydra.flyingcircus.io/build/402269/download/1/nixexprs.tar.xz",
        "release_metadata": {
            "channel_url": "https://hydra.flyingcircus.io/build/402269/download/1/nixexprs.tar.xz",
            "changelog_url": "https://doc.flyingcircus.io/platform/changes/2023/r020.html",
            "devhost_image_url": None,
            "devhost_image_hash": None,
            "image_url": None,
            "image_hash": None,
            "release_name": "stag_release_1",
            "rolling_channel": True,
        },
        "title": "[NixOS] fc-23.05-staging",
        "environment_class": "NixOS",
    },
]


def test_srihash_sha256():
    from fc.ceph.maintenance.images_nautilus import (
        sha256sum_to_sri,
        sri_to_sha256sum,
    )

    sri = "sha256-ZjBiODZlZTBkYzFlM2Y4Y2M0MTRiNzIzNWNhZjJmZjk1YmIxYjczNmY5OTE3ZjZmODViYjM2Yzg0NDVjOTU0Yg=="
    sha256 = "f0b86ee0dc1e3f8cc414b7235caf2ff95bb1b736f9917f6f85bb36c8445c954b"

    assert sha256sum_to_sri(sri_to_sha256sum(sri)) == sri
    assert sri_to_sha256sum(sha256sum_to_sri(sha256)) == sha256
    assert sri_to_sha256sum(sri) == sha256
    assert sha256sum_to_sri(sha256) == sri

    with pytest.raises(ValueError):
        sri_to_sha256sum("")
    with pytest.raises(ValueError):
        sri_to_sha256sum("md5-asdfk")
