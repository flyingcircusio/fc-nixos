{ lib
, stdenv
, makeWrapper
, fetchurl
, nodejs-10_x
, coreutils
, which
}:

with lib;
let
  nodejs = nodejs-10_x;

in stdenv.mkDerivation rec {
  pname = "opensearch-dashboards";
  version = "7.${realVersion}";
  realVersion = "1.3.0";

  src = fetchurl {
    url = "https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/${realVersion}/${pname}-${realVersion}-linux-x64.tar.gz";
    sha256 = "13ija5mnm4ydscf306pn362jsw5irac11fc2dalja0anzri7hgmp";
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

    ln -s $out/bin/opensearch-dashboards $out/bin/kibana
  '';

  meta = {
    description = "Visualize logs and time-stamped data";
    homepage = "http://www.elasticsearch.org/overview/opensearch-dashboards";
    license = licenses.asl20;
    platforms = with platforms; linux;
  };
}
