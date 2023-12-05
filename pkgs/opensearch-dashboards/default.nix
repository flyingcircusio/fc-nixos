{ lib
, stdenv
, makeWrapper
, fetchurl
, nodejs
, coreutils
, which
}:

with lib;

stdenv.mkDerivation rec {
  pname = "opensearch-dashboards";
  version = "2.11.0";

  src = fetchurl {
    url = "https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/${version}/${pname}-${version}-linux-x64.tar.gz";
    hash = "sha256-e6a0qE/idNf0NedfWugbh7qdBFNzDlnSnw/Gh/DEeGM=";
  };

  patches = [
    # OpenSearch Dashboard specifies that it wants nodejs 14.20.1 but nodejs in nixpkgs is at 14.21.1.
    ./disable-nodejs-version-check.patch
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
