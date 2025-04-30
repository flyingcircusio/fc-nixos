{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage rec {
  name = "sensu-syntax-${version}";
  version = "0.2.0";

  src = lib.cleanSource ./.;

  cargoHash = "sha256-eYEQXw/nB/dmIpNgvuvHQ/QwX7bv8j/zwoZrosOPyHM=";
  doCheck = true;

  meta = with lib; {
    description = "Sensu client config self-check";
    license = with licenses; [ bsd3 ];
  };
}
