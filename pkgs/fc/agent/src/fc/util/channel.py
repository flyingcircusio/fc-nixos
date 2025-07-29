import os
import os.path as p
import subprocess
import time
from pathlib import Path

from fc.util import nixos
from fc.util.lock import locked
from fc.util.nixos import RE_FC_CHANNEL, Specialisation


class Channel:
    REBOOT_DELAY = 10

    is_local = False

    def __init__(self, log, url, name="", environment=None, resolve_url=True):
        self.url = url
        self.name = name
        self.environment = environment
        self.system_path = None

        if url.startswith("file://"):
            self.is_local = True
            self.resolved_url = url.replace("file://", "")
        elif resolve_url:
            self.resolved_url = nixos.resolve_url_redirects(url)
        else:
            self.resolved_url = url

        self.log = log

        self.log_with_context = log.bind(
            url=self.resolved_url,
            name=name,
            environment=environment,
            is_local=self.is_local,
        )

    def version(self):
        if self.is_local:
            return "local-checkout"
        label_comp = [
            "/root/.nix-defexpr/channels/{}/{}".format(self.name, c)
            for c in [".version", ".version-suffix"]
        ]
        if all(p.exists(f) for f in label_comp):
            return "".join(open(f).read() for f in label_comp)

    def __str__(self):
        v = self.version() or "unknown"
        return "<Channel name={}, version={}, from={}>".format(
            self.name, v, self.resolved_url
        )

    def __eq__(self, other):
        if isinstance(other, Channel):
            return self.resolved_url == other.resolved_url
        return NotImplemented

    @classmethod
    def current(cls, log, channel_name):
        """Looks up existing channel by name.
        The URL found is usually already resolved (no redirects)
        so we don't do it again here. It can still be enabled with
        `resolve_url`, when needed.
        """
        if not p.exists("/root/.nix-channels"):
            log.debug("channel-current-no-nix-channels-dir")
            return
        with open("/root/.nix-channels") as f:
            for line in f.readlines():
                url, name = line.strip().split(" ", 1)
                if name == channel_name:
                    # We don't have to resolve the URL if it's a direct link
                    # to a Hydra build product. This is the normal case for
                    # running machines because the nixos channel is set to an
                    # already resolved URL.
                    # Resolve all other URLs, for example initial URLs used
                    # during VM bootstrapping.
                    resolve_url = RE_FC_CHANNEL.match(url) is None
                    log.debug(
                        "channel-current",
                        url=url,
                        name=name,
                        resolve_url=resolve_url,
                    )
                    return Channel(log, url, name, resolve_url=resolve_url)

        log.debug("channel-current-not-found", name=name)

    def load_nixos(self):
        self.log_with_context.debug("channel-load-nixos")

        if self.is_local:
            raise RuntimeError("`load` not applicable for local channels")

        nixos.update_system_channel(self.resolved_url, self.log)

    def check_local_channel(self):
        if not p.exists(p.join(self.resolved_url, "fc")):
            self.log_with_context.error(
                "local-channel-nix-path-invalid",
                _replace_msg="Expected NIX_PATH element 'fc' not found. Did you "
                "create a 'channels' directory via `dev-setup` and point "
                "the channel URL towards that directory?",
            )

    def switch(
        self,
        specialisation: str | Specialisation,
        lock_dir: Path,
        lazy=True,
        show_trace=False,
        switch_reboot=False,
    ) -> bool:
        """
        Build system with this channel and switch to it.
        Replicates the behaviour of nixos-rebuild switch and adds
        a "lazy mode" which only switches to the built system if it actually
        changed.
        """
        self.log_with_context.debug("channel-switch-start")
        # Put a temporary result link in /run to avoid a race condition
        # with the garbage collector which may remove the system we just built.
        # If register fails, we still hold a GC root until the next reboot.
        out_link = "/run/fc-agent-built-system"
        self.build(out_link, show_trace)
        nixos.register_system_profile(self.system_path, self.log)
        # New system is registered, delete the temporary result link.
        os.unlink(out_link)
        return self.switch_to_configuration(
            specialisation,
            lock_dir,
            lazy,
            switch_reboot,
        )

    def build(self, out_link=None, show_trace=False):
        """
        Build system with this channel. Works like nixos-rebuild build.
        Does not modify the running system.
        """
        self.log_with_context.debug("channel-build-start")

        if show_trace:
            build_options = ["--show-trace"]
        else:
            build_options = []

        if self.is_local:
            self.check_local_channel()
        system_path = nixos.build_system(
            channel_url=self.resolved_url,
            build_options=build_options,
            out_link=out_link,
            log=self.log,
        )
        self.system_path = system_path

    def switch_to_configuration(
        self,
        specialisation: str | Specialisation,
        lock_dir: Path,
        lazy=True,
        switch_reboot=False,
    ) -> bool:
        switch_path = nixos.get_specialisation_path_for_system(
            Path(self.system_path), specialisation, self.log
        )

        current_release = nixos.os_release()["VERSION_ID"]
        next_release = nixos.os_release(Path(switch_path))["VERSION_ID"]

        if current_release != next_release or switch_reboot:
            reboot_delay = self.REBOOT_DELAY
            if current_release != next_release:
                self.log.warn(
                    "release-change-requires-reboot",
                    current_release=current_release,
                    next_release=next_release,
                )
            else:
                self.log.warn(
                    "activate-with-reboot",
                    _replace_msg="Activating new system with reboot.",
                )
            while reboot_delay:
                self.log.warn(
                    "reboot-scheduled",
                    _replace_msg=f"WILL REBOOT IN {reboot_delay} SECONDS. PRESS Ctrl-C TO ABORT.",
                )
                time.sleep(1)
                reboot_delay -= 1
            with locked(self.log, lock_dir, "switch_to_configuration.lock"):
                if not nixos.switch_to_system(
                    switch_path, lazy, "boot", self.log
                ):
                    return False
            self.log.warn(
                "reboot-scheduled",
                _replace_msg="System switched. Triggering reboot NOW.",
            )
            subprocess.check_call(["reboot"])
            return True
        else:
            with locked(self.log, lock_dir, "switch_to_configuration.lock"):
                return nixos.switch_to_system(
                    switch_path, lazy, "switch", self.log
                )

    def dry_activate(self):
        return nixos.dry_activate_system(self.system_path, self.log)
