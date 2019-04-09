{ pkgs, callPackage }:

{
  recurseForDerivations = true;

  agent = callPackage ./agent {};
  box = callPackage ./box {
    rustPlatform = pkgs.rustPlatform_1_31;
  };
  check-journal = callPackage ./check-journal.nix {
    rustPlatform = pkgs.rustPlatform_1_31;
  };
  collectdproxy = callPackage ./collectdproxy {};
  fix-so-rpath = callPackage ./fix-so-rpath {};
  logcheckhelper = callPackage ./logcheckhelper {
    rustPlatform = pkgs.rustPlatform_1_31;
  };
  multiping = callPackage ./multiping.nix {
    rustPlatform = pkgs.rustPlatform_1_31;
  };
  sensusyntax = callPackage ./sensusyntax {
    rustPlatform = pkgs.rustPlatform_1_31;
  };
  sensuplugins = callPackage ./sensuplugins {};
  userscan = callPackage ./userscan.nix {
    rustPlatform = pkgs.rustPlatform_1_31;
  };
}
