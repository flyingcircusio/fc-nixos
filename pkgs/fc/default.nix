{ pkgs, pkgs-19_09, callPackage }:

{
  recurseForDerivations = true;

  agent = callPackage ./agent {};
  box = callPackage ./box { };
  check-haproxy = callPackage ./check-haproxy { };
  check-journal = callPackage ./check-journal.nix { };
  collectdproxy = callPackage ./collectdproxy {};
  fix-so-rpath = callPackage ./fix-so-rpath {};
  logcheckhelper = callPackage ./logcheckhelper { };
  multiping = callPackage ./multiping.nix { };
  sensusyntax = callPackage ./sensusyntax { };
  sensuplugins = callPackage ./sensuplugins {};
  userscan = pkgs-19_09.callPackage ./userscan.nix { };
}
