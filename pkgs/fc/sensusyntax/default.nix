{ stdenv, lib, rustPlatform, docutils }:

rustPlatform.buildRustPackage rec {
  name = "sensu-syntax-${version}";
  version = "0.2.0";

  src = lib.cleanSource ./.;
  cargoSha256 = "0p0kwbbr8camiaragbs8yi3jk91l7d6psmhkw5f3x1p76134i4k7";
  doCheck = true;

  meta = with stdenv.lib; {
    description = "Sensu client config self-check";
    license = with licenses; [ bsd3 ];
    platforms = platforms.all;
  };
}
