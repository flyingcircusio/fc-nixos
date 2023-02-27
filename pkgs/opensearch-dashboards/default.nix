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
  version = "2.5.0";

  src = fetchurl {
    url = "https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/${version}/${pname}-${version}-linux-x64.tar.gz";
    sha256 = "sha256-bKrdWFHvBZvQfvIUvJVwkRsXigDld8/XxSWpK2W18Gg=";
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
