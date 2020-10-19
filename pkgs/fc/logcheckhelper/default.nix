{ pkgs, stdenv, rustPlatform }:

with rustPlatform;

buildRustPackage rec {
  name = "logcheck-helper-${version}";
  version = "1.0.1";
  src = ./logcheck-helper;
  cargoSha256 = "1m6wnyi8zimy5nznyxqvhb1brmjzcpagmddy0cvcfrfa4xsm98ap";
  doCheck = false;

  meta = with stdenv.lib; {
    description = ''
      Derive a correct regular expression for logcheck ignore patterns
    '';
    license = with licenses; [ bsd3 ];
    maintainer = with maintainers; [ ckauhaus ];
  };
}
