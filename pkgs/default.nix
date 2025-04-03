# Collection of own packages
{ pkgs, pyPackages }:

let
  self = {
    callPackage = pkgs.newScope self;

    fc = import ./fc {
      inherit (self) callPackage;
      inherit pkgs pyPackages;
    };

  };

in
self.fc
