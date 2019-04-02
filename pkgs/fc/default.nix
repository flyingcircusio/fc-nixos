{ pkgs, callPackage }:

{
  recurseForDerivations = true;

  agent = callPackage ./agent {};
  box = callPackage ./box {
    rustPlatform = pkgs.rustPlatform_1_31;
  };
  check-journal = callPackage ./check-journal.nix { };
  collectdproxy = callPackage ./collectdproxy { };
  fix-so-rpath = callPackage ./fix-so-rpath { };
  logcheckhelper = callPackage ./logcheckhelper {};
  multiping = callPackage ./multiping.nix {};
  sensusyntax = callPackage ./sensusyntax {
    rustPlatform = pkgs.rustPlatform_1_31;
  };
  sensuplugins = callPackage ./sensuplugins {};
  userscan = callPackage ./userscan.nix {
    rustPlatform = pkgs.rustPlatform_1_31;
  };
}
