# Collection of own packages
{ pkgs
, pkgs-unstable
}:

let
  self = {
    callPackage = pkgs.newScope self;

    fc = import ./fc {
      inherit (self) callPackage;
      inherit pkgs pkgs-unstable;
    };

  };

in self.fc
