{ pkgs, lib, rustPlatform }:

with rustPlatform;

buildRustPackage rec {
  name = "logcheck-helper-${version}";
  version = "1.0.1";
  src = ./logcheck-helper;
  cargoHash = "sha256-WolbcPc+PuFYsTh+QRV17KPhz2f5MPkWsft244tQbzQ=";
  doCheck = false;

  meta = with lib; {
    description = ''
      Derive a correct regular expression for logcheck ignore patterns
    '';
    license = with licenses; [ bsd3 ];
    maintainer = with maintainers; [ ckauhaus ];
  };
}
