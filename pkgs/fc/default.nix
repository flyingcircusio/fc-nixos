{ pkgs, callPackage }:

{
  recurseForDerivations = true;

  check-journal = pkgs.callPackage ./check-journal.nix { };
  agent = callPackage ./agent {};
  box = callPackage ./box {};
  logcheckhelper = callPackage ./logcheckhelper {};
  multiping = callPackage ./multiping.nix {};
  userscan = callPackage ./userscan.nix {};
}
