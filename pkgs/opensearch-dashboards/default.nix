{ lib
, stdenv
, makeWrapper
, fetchurl
, nodejs-14_x
, coreutils
, which
}:

with lib;
let
  nodejs = nodejs-14_x;

in stdenv.mkDerivation rec {
  pname = "opensearch-dashboards";
  version = "1.3.8";

  src = fetchurl {
    url = "https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/${version}/${pname}-${version}-linux-x64.tar.gz";
    sha256 = "sha256-5oWSThzo/SKatRAPAEOisVAwOGX3WU3kGGU0/xZ3rUM=";
  };

  patches = [
  ];

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/libexec/opensearch-dashboards $out/bin
    mv * $out/libexec/opensearch-dashboards/
    rm -r $out/libexec/opensearch-dashboards/node
    makeWrapper $out/libexec/opensearch-dashboards/bin/opensearch-dashboards $out/bin/opensearch-dashboards \
      --prefix PATH : "${lib.makeBinPath [ nodejs coreutils which ]}"
    sed -i 's@NODE=.*@NODE=${nodejs}/bin/node@' $out/libexec/opensearch-dashboards/bin/opensearch-dashboards
  '';

  meta = {
    description = "Visualization and user interface for OpenSearch";
    homepage = "https://opensearch.org";
    license = licenses.asl20;
    platforms = with platforms; linux;
  };
}
