{ pkgs, pkgs-19_09, callPackage }:

{
  recurseForDerivations = true;

  agent = callPackage ./agent {};
  box = callPackage ./box { };
  check-haproxy = callPackage ./check-haproxy {};
  check-journal = callPackage ./check-journal.nix {};
  check-postfix = pkgs-19_09.callPackage ./check-postfix {};
  collectdproxy = callPackage ./collectdproxy {};
  roundcube-chpasswd = pkgs-19_09.callPackage ./roundcube-chpasswd {};
  fix-so-rpath = callPackage ./fix-so-rpath {};
  logcheckhelper = callPackage ./logcheckhelper { };
  multiping = callPackage ./multiping.nix {};
  sensuplugins = callPackage ./sensuplugins {};
  sensusyntax = callPackage ./sensusyntax {};
  userscan = pkgs-19_09.callPackage ./userscan.nix {};
}
