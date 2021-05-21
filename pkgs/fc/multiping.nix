{ pkgs, lib, fetchFromGitHub, rustPlatform }:

with rustPlatform;

buildRustPackage rec {
  name = "multiping-${version}";
  version = "1.1.1";

  src = fetchFromGitHub {
    owner = "ckauhaus";
    repo = "multiping";
    rev = version;
    sha256 = "19whh7xzk2sqnrgkyw6gmmq5kn9pmbma5nnl6zc4iz4wa9slysl4";
  };

  cargoSha256 = "091yr17df0qf2n4dv0xifrv25z774ikmw9ysk4kd8xl2shijkxr9";
  RUSTFLAGS = "--cfg feature=\"oldglibc\"";

  meta = with lib; {
    description = ''
      Pings multiple targets in parallel to check outgoing connectivity.
    '';
    homepage = "https://flyingcircus.io";
    license = with licenses; [ bsd3 ];
  };
}
