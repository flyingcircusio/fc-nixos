{
  lib,
  rustPlatform,
}:

with rustPlatform;

buildRustPackage rec {
  name = "logcheck-helper-${version}";
  version = "1.0.1";
  src = ./logcheck-helper;

  cargoHash = "sha256-Ys/SI7ESjj3GFmR8WQUDNuvtNGC/e2Vwsn5GGd4BdmQ=";
  doCheck = false;

  meta = with lib; {
    description = ''
      Derive a correct regular expression for logcheck ignore patterns
    '';
    license = with licenses; [ bsd3 ];
    maintainer = with maintainers; [ ckauhaus ];
  };
}
