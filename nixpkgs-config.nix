# Common nixpkgs config used by platform code (nixos/platform/default.nix)
# and our customized nixpkgs from ./default.nix.
{
  allowedUnfreePackageNames = [
    # TODO: megacli is only used on physical machines but pulled in by
    # fc-sensuplugins and thus needed on all machines. Should be moved to
    # the raid service after decoupling fc-sensuplugins.
    "megacli"
    # MongoDB starting with 4.0 uses the SSPL license, which is declared
    # as unfree. We don't have alternatives to mongodb right now so we have
    # to enable it.
    "mongodb"
  ];

  permittedInsecurePackages = [
    "imagemagick-6.9.12-68" # Legacy, but gets updates. Customer still needs it.
    "nodejs-14.21.3" # Needed for opensearch-dashboards.
    "nodejs-16.20.1" # EOL 2023-09-11, needed for discourse and some customers.
    "openssl-1.1.1v" # EOL 2023-09-11, needed for Percona and older PHP versions.
    "python-2.7.18.6" # Needed for some legacy customer applications.
    "ruby-2.7.8" # EOL 2023-03-31, needed for Sensu checks
  ];
}
