self: super:
{
  # own packages
  inherit (import ./. { pkgs = self; }) fc;

  # overrides for upstream packages
  collectdproxy = super.callPackage ./collectdproxy {};
}
