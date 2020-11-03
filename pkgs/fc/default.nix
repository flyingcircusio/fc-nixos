{ pkgs, pkgs-unstable, callPackage }:

{
  recurseForDerivations = true;

  agent = callPackage ./agent {};
  check-age = pkgs-unstable.callPackage ./check-age {};
  check-haproxy = callPackage ./check-haproxy {};
  check-journal = callPackage ./check-journal.nix {};
  check-mongodb = callPackage ./check-mongodb {};
  check-postfix = pkgs-unstable.callPackage ./check-postfix {};
  collectdproxy = callPackage ./collectdproxy {};
  roundcube-chpasswd = pkgs-unstable.callPackage ./roundcube-chpasswd {};
  fix-so-rpath = callPackage ./fix-so-rpath {};
  logcheckhelper = callPackage ./logcheckhelper { };
  multiping = callPackage ./multiping.nix {};
  sensuplugins = callPackage ./sensuplugins {};
  sensusyntax = callPackage ./sensusyntax {};
  userscan = pkgs-unstable.callPackage ./userscan.nix {};
}
