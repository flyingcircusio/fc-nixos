# Collection of own packages
{ pkgs
, pkgs-20_03
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
