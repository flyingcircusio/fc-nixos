{ pkgs, callPackage }:

{
  recurseForDerivations = true;

  userscan = callPackage ./userscan.nix {};
  multiping = callPackage ./multiping.nix {};
}
