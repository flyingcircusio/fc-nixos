{ pkgs, callPackage }:

{
  userscan = callPackage ./userscan.nix {};
}
