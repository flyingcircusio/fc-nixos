{ pkgs, stdenv, rustPlatform }:

with rustPlatform;

buildRustPackage rec {
  name = "logcheck-helper";
  src = ./logcheck-helper;
  cargoSha256 = "1kg6lrmc348y87pz1ivpaz8cbv88vzzdi7pa7v41371kh718m6mw";
  doCheck = false;

  meta = with stdenv.lib; {
    description = "Derive a correct regular expression for logcheck ignore patterns";
    license = with licenses; [ bsd3 ];
  };
}
