from batou.component import Component
from batou.lib.file import File


class Ceph(Component):
    def configure(self):
        # keep constants in sync with init_cluster.py
        self.provide(
            "enc",
            {
                "roles": ["ceph_mon", "ceph_osd"],
                "parameters": {
                    "location": "test",
                    "resource_group": "services",
                    "secret_salt": "salt-for-${config.networking.hostName}-dhkasjy9",
                    "secrets": {
                        "ceph/admin_key": "AQBFJa9hAAAAABAAtdggM3mhVBAEYw3+Loehqw==",
                    },
                },
            },
        )

        self += File("init_cluster.py", is_template=False, mode=0o755)
        self |= (ceph_nix := File("/etc/local/nixos/ceph.nix"))
        self.provide("nixos-config", ceph_nix)
