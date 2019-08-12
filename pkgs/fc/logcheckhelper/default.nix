{ pkgs, stdenv, rustPlatform }:

with rustPlatform;

buildRustPackage rec {
  name = "logcheck-helper";
  src = ./logcheck-helper;
  cargoSha256 = "0cngyxlhskrb616qck0hidn879nwbyvh7p4p14134y65gp3ckn6i";
  doCheck = false;

  meta = with stdenv.lib; {
    description = "Derive a correct regular expression for logcheck ignore patterns";
    license = with licenses; [ bsd3 ];
    platforms = platforms.all;
  };
}
