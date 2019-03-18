self: super:
{
  # own packages go here
  inherit (import ./default.nix { pkgs = self; }) fc;

  # overrides for upstream packages follow
  collectdproxy = super.callPackage ./collectdproxy {};

  # we use a newer version than on upstream
  vulnix = super.callPackage ./vulnix.nix {
    pythonPackages = self.python3Packages;
  };
}
