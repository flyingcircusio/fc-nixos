import json
from pathlib import Path

from batou.component import Attribute, Component
from batou.lib.file import File
from batou.utils import Address


def update_merge(d1, d2):
    d1 = d1.copy()
    for k, v in d2.items():
        # No collision, simply add the key
        if k in d1:
            # Collision: lists are copied and extended
            if isinstance(v, list):
                v = list(d1[k]) + v
            # Collision: dicts are recursively merged
            elif isinstance(v, dict):
                v = update_merge(d1[k], v)
        # Replace old value with new (merged) value
        d1[k] = v
    return d1


class JSONUpdate(Component):
    namevar = "path"
    updates: list[dict] = Attribute()

    def configure(self):
        self._path = self.path
        self.path = self.map(self.path)

    def verify(self):
        # If we don't find anything, then we'll just write out what we have
        self.new_data = {}
        for update in self.updates:
            self.new_data = update_merge(self.new_data, update)

        p = Path(self.path)
        assert p.exists()
        try:
            with p.open() as f:
                current_data = json.load(f)
        except Exception:
            assert False
        self.new_data = update_merge(current_data, self.new_data)
        assert self.new_data == current_data

    def update(self):
        with Path(self.path).open("w") as f:
            json.dump(self.new_data, f, indent=2)


class PurgeUnknownSnippets(Component):
    namevar = "pattern"
    keep: list = Attribute()

    def configure(self):
        assert self.pattern.startswith("/")
        self.pattern = self.pattern.lstrip("/")
        self._keep = set(Path(x.path) for x in self.keep)

    def verify(self):
        self._to_delete = set()
        for path in Path("/").glob(self.pattern):
            if path not in self._keep:
                self._to_delete.add(path)
        assert not self._to_delete

    def update(self):
        for path in self._to_delete:
            path.unlink()


class NixOS(Component):
    def configure(self):
        enc = {
            "name": self.host._name,
            "parameters": {
                "directory_password": "password-for-fake-directory",
                "directory_url": "http://localhost:82",
                "directory_ring": 0,
                "resource_group": "test",
                "location": "test",
                "environment_url": "file:///home/developer/fc-nixos/channels",
                "kvm_net_memory": "2000",
                # This secret needs to be kept in sync with the
                # ENC in the ceph-nautilus.nix test suite.
                "secret_salt": f"salt-for-{self.host._name}-dhkasjy9",
                "secrets": {
                    "ceph/admin_key": "AQBFJa9hAAAAABAAtdggM3mhVBAEYw3+Loehqw==",
                },
            },
        }

        # Our dependencies are reversed: we first need to configure the
        # NixOS environment and then the individual parts can do their work
        self += (
            enc := JSONUpdate(
                "/etc/nixos/enc.json",
                updates=[enc]
                + list(self.require("enc", host=self.host, reverse=True)),
            )
        )

        self.host1_addr = Address("host1:0")
        self.host2_addr = Address("host2:0")
        self += (base := File("/etc/local/nixos/base.nix"))

        # Those snippets would typically be File components that place
        # stuff in /etc/local/nixos/
        snippets = self.require("nixos-config", host=self.host, reverse=True)
        for snippet in snippets:
            self += snippet

        snippets.append(enc)
        snippets.append(base)

        self += PurgeUnknownSnippets("/etc/local/nixos/*.nix", keep=snippets)

    def verify(self):
        self.assert_no_subcomponent_changes()

    def update(self):
        if Path("/home/developer/fc-nixos").exists():
            with self.chdir("/home/developer/fc-nixos"):
                self.cmd("./dev-setup")
        self.cmd("fc-manage switch")
