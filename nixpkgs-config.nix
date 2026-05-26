# Common nixpkgs config used by platform code (nixos/platform/default.nix)
# and our customized nixpkgs from ./default.nix.
{
  allowedUnfreePackageNames = [
    # TODO: megacli is only used on physical machines but pulled in by
    # fc-sensuplugins and thus needed on all machines. Should be moved to
    # the raid service after decoupling fc-sensuplugins.
    "megacli"
    "consul"
  ];

  permittedInsecurePackages = [
    "imagemagick-6.9.13-38" # Legacy, but gets updates. Customer still needs it.
    "openssl-1.1.1w" # EOL 2023-09-11, needed for Percona and older PHP versions.
    "python-2.7.18.12" # Needed for some legacy customer applications.
    "ruby-2.7.8" # EOL 2023-03-31, needed for Sensu checks
    "docker-24.0.9" # Old installs still use storage driver removed in 25.x.
    "jitsi-meet-1.0.8792" # insecure libolm but this only affects optional e2ee which we don't really support.
    "k3s-1.31.14+k3s1" # EOL, but we want to keep it
    "varnish-7.7.3" # EOL, known vulnerability (FC-52533). We will also recommend updating to varnish8, but there are breaking config changes.
    "nodejs-slim-20.20.2" # EOL, required by github-runner
    "imagemagick-6.9.13-48" # We're warning already that imagemagick 6 is EOL, but still allow it. See pkgs/overlay.nix
  ];
}
