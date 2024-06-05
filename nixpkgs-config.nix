# Common nixpkgs config used by platform code (nixos/platform/default.nix)
# and our customized nixpkgs from ./default.nix.
{
  allowedUnfreePackageNames = [
    # TODO: megacli is only used on physical machines but pulled in by
    # fc-sensuplugins and thus needed on all machines. Should be moved to
    # the raid service after decoupling fc-sensuplugins.
    "megacli"
  ];

  permittedInsecurePackages = [
    "imagemagick-6.9.13-10" # Legacy, but gets updates. Customer still needs it.
    "openssl-1.1.1w" # EOL 2023-09-11, needed for Percona and older PHP versions.
    "python-2.7.18.8" # Needed for some legacy customer applications.
    "ruby-2.7.8" # EOL 2023-03-31, needed for Sensu checks
  ];
}
