{ pkgs, pkgs-unstable, callPackage }:

{
  recurseForDerivations = true;

  agent = callPackage ./agent {};
  box = callPackage ./box { };
  check-haproxy = callPackage ./check-haproxy {};
  check-journal = callPackage ./check-journal.nix {};
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
