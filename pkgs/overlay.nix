self: super:

let
  versions = import ../nixpkgs.nix { pkgs = super; };
  pkgs-18_03 = import versions.nixos-18_03 {};

in {
  #
  # == our own stuff
  #
  fc = (import ./default.nix { pkgs = self; });

  #
  # == imports from older nixpkgs ==
  #
  inherit (pkgs-18_03)
    nodejs-9_x
    php56
    php56Packages;

  docsplit = super.callPackage ./docsplit { };

  # we use a newer version than on upstream
  vulnix = super.callPackage ./vulnix.nix {
    pythonPackages = self.python3Packages;
  };
}
