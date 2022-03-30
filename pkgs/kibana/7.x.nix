{ elasticKibanaOSS7Version
, lib, stdenv
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
  name = "kibana-oss-${version}";
  version = elasticKibanaOSS7Version;

  src = fetchurl {
    url = "https://artifacts.elastic.co/downloads/kibana/${name}-linux-x86_64.tar.gz";
    sha256 = "050rhx82rqpgqssp1rdflz1ska3f179kd2k2xznb39614nk0m6gs";
  };

  patches = [
    # Kibana specifies it specifically needs nodejs 10.15.2 but nodejs in nixpkgs is at a higher version.
    ./disable-nodejs-version-check-7.patch
  ];

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/libexec/kibana $out/bin
    mv * $out/libexec/kibana/
    rm -r $out/libexec/kibana/node
    makeWrapper $out/libexec/kibana/bin/kibana $out/bin/kibana \
      --prefix PATH : "${lib.makeBinPath [ nodejs coreutils which ]}"
    sed -i 's@NODE=.*@NODE=${nodejs}/bin/node@' $out/libexec/kibana/bin/kibana
  '';

  meta = {
    description = "Visualize logs and time-stamped data";
    homepage = "http://www.elasticsearch.org/overview/kibana";
    license = licenses.asl20;
    platforms = with platforms; linux;
  };
}
