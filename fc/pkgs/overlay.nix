self: super:
{
  # FCIO generic library functions - access with pkgs.fclib.*
  fclib = super.callPackage ./fclib {};

  collectdproxy = super.callPackage ./collectdproxy {};

  fc-userscan = super.callPackage ./fc-userscan.nix {};
}
