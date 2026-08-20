import os.path as p

from fc.util import nixos


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
        from fc.util.nixos import RE_FC_CHANNEL

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
        self.log.debug(
            "channel-load-nixos",
            url=self.resolved_url,
            name=self.name,
            environment=self.environment,
            is_local=self.is_local,
        )

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
                url=self.resolved_url,
                name=self.name,
                environment=self.environment,
                is_local=self.is_local,
            )
