{ pkgs, lib, rustPlatform }:

with rustPlatform;

buildRustPackage rec {
  name = "logcheck-helper-${version}";
  version = "1.0.1";
  src = ./logcheck-helper;
  cargoSha256 = "0d3ga25y6xpvn4bgjc7rcz7y38zcflal2ziqn5cf2giyyxq5p2as";
  doCheck = false;

  meta = with lib; {
    description = ''
      Derive a correct regular expression for logcheck ignore patterns
    '';
    license = with licenses; [ bsd3 ];
    maintainer = with maintainers; [ ckauhaus ];
  };
}
