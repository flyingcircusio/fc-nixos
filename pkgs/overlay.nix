self: super:
{
  # XXX move to config.lib
  #fclib = super.callPackage ./fclib {};

  collectdproxy = super.callPackage ./collectdproxy {};

  fc-userscan = super.callPackage ./fc-userscan.nix {};
}
