{ pkgs, stdenv, fetchFromGitHub, rustPlatform }:

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

  cargoSha256 = "17qxbm0wchqhlg2xmqghvvmgxa7rg6qfa200w90bp5hm0v350439";
  RUSTFLAGS = "--cfg feature=\"oldglibc\"";

  meta = with stdenv.lib; {
    description = ''
      Pings multiple targets in parallel to check outgoing connectivity.
    '';
    homepage = "https://flyingcircus.io";
    license = with licenses; [ bsd3 ];
  };
}
