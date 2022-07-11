# Common nixpkgs config used by platform code (nixos/platform/default.nix)
# and our customized nixpkgs from ./default.nix.
{
  allowedUnfreePackageNames = [
    # TODO: megacli is only used on physical machines but pulled in by
    # fc-sensuplugins and thus needed on all machines. Should be moved to
    # the raid service after decoupling fc-sensuplugins.
    "megacli"
    # We could also allow SSPL as a whole, but adding sspl to
    # allowlistLicenses is broken in 21.11. Fixed in unstable:
    # https://github.com/NixOS/nixpkgs/pull/160467
    # TODO: replace this when on 22.05.
    "mongodb"
  ];

  permittedInsecurePackages = [
    "nodejs-10.24.1"
    "mongodb-3.6.23"
  ];
}
