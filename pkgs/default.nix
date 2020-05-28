# Collection of own packages
{ pkgs ? import <nixpkgs> {}
, pkgs-20_03 ? import <nixpkgs> {}
}:

let
  self = {
    callPackage = pkgs.newScope self;

    fc = import ./fc {
      inherit (self) callPackage;
      inherit pkgs pkgs-20_03;
    };

  };

in self.fc
