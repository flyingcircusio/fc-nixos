from batou.component import Component
from batou.lib.file import File


class Ceph(Component):
    def configure(self):
        self.provide("enc", {"roles": ["ceph_mon", "ceph_osd"]})

        self += File("init_cluster.py", is_template=False, mode=0o755)
        self |= (ceph_nix := File("/etc/local/nixos/ceph.nix"))
        self.provide("nixos-config", ceph_nix)
