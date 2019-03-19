# Collection of own packages
{ pkgs ? import <nixpkgs> {} }:

let
  self = {
    callPackage = pkgs.newScope self;

    fc = import ./fc {
      inherit (self) callPackage;
      inherit pkgs;
    };

  };

in self.fc
