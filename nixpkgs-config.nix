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
    "nodejs-10.24.1"
    "mongodb-3.6.23"
  ];
}
