{ pkgs, pkgs-20_03, callPackage }:

{
  recurseForDerivations = true;

  agent = callPackage ./agent {};
  box = callPackage ./box { };
  check-haproxy = callPackage ./check-haproxy {};
  check-journal = callPackage ./check-journal.nix {};
  check-postfix = pkgs-20_03.callPackage ./check-postfix {};
  collectdproxy = callPackage ./collectdproxy {};
  roundcube-chpasswd = pkgs-20_03.callPackage ./roundcube-chpasswd {};
  fix-so-rpath = callPackage ./fix-so-rpath {};
  logcheckhelper = callPackage ./logcheckhelper { };
  multiping = callPackage ./multiping.nix {};
  sensuplugins = callPackage ./sensuplugins {};
  sensusyntax = callPackage ./sensusyntax {};
  userscan = pkgs-20_03.callPackage ./userscan.nix {};
}
