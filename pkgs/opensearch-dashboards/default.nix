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
  version = "1.3.1";

  src = fetchurl {
    url = "https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/${version}/${pname}-${version}-linux-x64.tar.gz";
    sha256 = "1dxx5hrdjqny3vm4b0209y7s8nr6a0rx9mg9vvyqsmyz9159d1s8";
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
    description = "Visualize logs and time-stamped data";
    homepage = "http://www.elasticsearch.org/overview/opensearch-dashboards";
    license = licenses.asl20;
    platforms = with platforms; linux;
  };
}
