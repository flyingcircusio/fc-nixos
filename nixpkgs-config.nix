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
    "openssl-1.1.1w" # EOL 2023-09-11, needed for Percona and older PHP versions.
    "python-2.7.18.12" # Needed for some legacy customer applications.
    "ruby-2.7.8" # EOL 2023-03-31, needed for Sensu checks
    "jitsi-meet-1.0.9365" # insecure libolm but this only affects optional e2ee which we don't really support.
    "nodejs-slim-20.20.2" # EOL, required by github-runner
    "nodejs-20.20.2" # EOL, required by github-runner
  ];
}
