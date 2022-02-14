{ lib, rustPlatform, docutils }:

rustPlatform.buildRustPackage rec {
  name = "sensu-syntax-${version}";
  version = "0.2.0";

  src = lib.cleanSource ./.;
  cargoSha256 = "sha256-IMn2XNm+yEQfYxtIB3RtWQO4nRt1B9haeri5vSBEAOQ=";
  doCheck = true;

  meta = with lib; {
    description = "Sensu client config self-check";
    license = with licenses; [ bsd3 ];
  };
}
