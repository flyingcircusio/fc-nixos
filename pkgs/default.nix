# Collection of own packages
{ pkgs ? import <nixpkgs> {}
, pkgs-19_09 ? import <nixpkgs> {}
}:

let
  self = {
    callPackage = pkgs.newScope self;

    fc = import ./fc {
      inherit (self) callPackage;
      inherit pkgs pkgs-19_09;
    };

  };

in self.fc
