{ pkgs, callPackage }:

{
  recurseForDerivations = true;

  agent = callPackage ./agent {};
  box = callPackage ./box {};
  logcheckhelper = callPackage ./logcheckhelper {};
  multiping = callPackage ./multiping.nix {};
  userscan = callPackage ./userscan.nix {};
}
