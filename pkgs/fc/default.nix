{ pkgs, callPackage }:

{
  recurseForDerivations = true;

  agent = callPackage ./agent {};
  box = callPackage ./box {};
  check-journal = pkgs.callPackage ./check-journal.nix { };
  collectdproxy = callPackage ./collectdproxy { };
  fix-so-rpath = callPackage ./fix-so-rpath { };
  logcheckhelper = callPackage ./logcheckhelper {};
  multiping = callPackage ./multiping.nix {};
  sensusyntax = callPackage ./sensusyntax {};
  userscan = callPackage ./userscan.nix {};
}
