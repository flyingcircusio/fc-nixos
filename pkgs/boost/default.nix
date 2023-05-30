{ lib
, callPackage
, boost-build
, fetchurl
}:

let
  makeBoost = file:
    lib.fix (self:
      callPackage file {
        boost-build = boost-build.override {
          # useBoost allows us passing in src and version from
          # the derivation we are building to get a matching b2 version.
          useBoost = self;
        };
      }
    );
in {
  boost159 = makeBoost ./1.59.nix;
}
