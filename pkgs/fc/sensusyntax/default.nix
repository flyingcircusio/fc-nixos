{ lib, rustPlatform, docutils }:

rustPlatform.buildRustPackage rec {
  name = "sensu-syntax-${version}";
  version = "0.2.0";

  src = lib.cleanSource ./.;
  cargoSha256 = "1q5qs3yj7w01vpcjqc9nyid24q0z7pa3hb301icjhapfv69rfy3y";
  doCheck = true;

  meta = with lib; {
    description = "Sensu client config self-check";
    license = with licenses; [ bsd3 ];
  };
}
