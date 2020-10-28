# Collection of own packages
{ pkgs }:

let
  self = {
    callPackage = pkgs.newScope self;

    fc = import ./fc {
      inherit (self) callPackage;
      inherit pkgs;
    };

  };

in self.fc
