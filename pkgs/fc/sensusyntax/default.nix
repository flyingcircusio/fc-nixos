{
  lib,
  rustPlatform,
}:

rustPlatform.buildRustPackage rec {
  name = "sensu-syntax-${version}";
  version = "0.2.0";

  src = lib.cleanSource ./.;
  # FIXME: need to migrate to new cargo fetcher, but currently generates
  # a key error during locking.
  #useFetchCargoVendor = true;
  cargoHash = "sha256-IMn2XNm+yEQfYxtIB3RtWQO4nRt1B9haeri5vSBEAOQ=";
  doCheck = true;

  meta = with lib; {
    description = "Sensu client config self-check";
    license = with licenses; [ bsd3 ];
  };
}
