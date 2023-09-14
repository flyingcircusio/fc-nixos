# Collection of own packages
{ pkgs, pythonPackages }:

let
  self = {
    callPackage = pkgs.newScope self;

    fc = import ./fc {
      inherit (self) callPackage;
      inherit pkgs pythonPackages;
    };

  };

in self.fc
