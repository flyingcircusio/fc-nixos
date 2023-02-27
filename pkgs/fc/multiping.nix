{ pkgs, lib, fetchFromGitHub, rustPlatform }:

with rustPlatform;

buildRustPackage rec {
  name = "multiping-${version}";
  version = "1.1.2-gb49b357";

  src = fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "multiping";
    rev = "b49b3575c3e3c298851d22a8b219dbaf470afe07";
    sha256 = "DPjrnzEo//z41422GyCwL2T/quMdlKKk09Mpazpg30E=";
  };

  cargoHash = "sha256-xi00EMfiZBl5TTIQC2GdiaEP72arFqt77EqCBy/l5O4=";
  RUSTFLAGS = "--cfg feature=\"oldglibc\"";

  meta = with lib; {
    description = ''
      Pings multiple targets in parallel to check outgoing connectivity.
    '';
    homepage = "https://flyingcircus.io";
    license = with licenses; [ bsd3 ];
  };
}
