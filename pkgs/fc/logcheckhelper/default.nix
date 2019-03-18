{ pkgs, stdenv, rustPlatform }:

with rustPlatform;

buildRustPackage rec {
  name = "logcheck-helper";
  src = ./logcheck-helper;
  cargoSha256 = "156yf1cmwnc7wbfr9dad7zfna5syx0kninw8510vsadiqn1ycah6";
  doCheck = false;

  meta = with stdenv.lib; {
    description = "Derive a correct regular expression for logcheck ignore patterns";
    license = with licenses; [ bsd3 ];
    platforms = platforms.all;
  };
}

