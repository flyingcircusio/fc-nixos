{ pkgs, pkgs-19_09, callPackage }:

{
  recurseForDerivations = true;

  agent = callPackage ./agent {};
  box = callPackage ./box { };
  check-journal = callPackage ./check-journal.nix {};
  check-haproxy = callPackage ./check-haproxy {};
  collectdproxy = callPackage ./collectdproxy {};
  roundcube-chpasswd = pkgs-19_09.callPackage ./roundcube-chpasswd {};
  fix-so-rpath = callPackage ./fix-so-rpath {};
  logcheckhelper = callPackage ./logcheckhelper { };
  multiping = callPackage ./multiping.nix {};
  sensuplugins = callPackage ./sensuplugins {};
  sensusyntax = callPackage ./sensusyntax {};
  userscan = pkgs-19_09.callPackage ./userscan.nix {};
}
