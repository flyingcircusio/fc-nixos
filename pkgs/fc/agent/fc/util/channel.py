import os
import os.path as p

from fc.util import nixos
from fc.util.nixos import RE_FC_CHANNEL


class Channel:
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

    def switch(self, lazy=True, show_trace=False):
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
        return nixos.switch_to_system(self.system_path, lazy, self.log)

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
            self.resolved_url, build_options, out_link, self.log
        )
        self.system_path = system_path

    def dry_activate(self):
        return nixos.dry_activate_system(self.system_path, self.log)
