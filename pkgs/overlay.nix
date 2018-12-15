self: super:
{
  # own packages go here
  inherit (import ./default.nix { pkgs = self; }) fc;

  # overrides for upstream packages follow
  collectdproxy = super.callPackage ./collectdproxy {};
}
