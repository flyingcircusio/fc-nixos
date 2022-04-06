{ elasticKibana7Version
, lib, stdenv
, makeWrapper
, fetchurl
, nodejs-10_x
, coreutils
, which
, unfree ? false
}:

with lib;
let
  nodejs = nodejs-10_x;

in stdenv.mkDerivation rec {
  flavour = if unfree then "" else "-oss";
  name = "kibana${flavour}-${version}";
  version = elasticKibana7Version;

  src = fetchurl {
    url = "https://artifacts.elastic.co/downloads/kibana/${name}-linux-x86_64.tar.gz";
    sha256 =
      if unfree
      then "06p0v39ih606mdq2nsdgi5m7y1iynk9ljb9457h5rrx6jakc2cwm"
      else "050rhx82rqpgqssp1rdflz1ska3f179kd2k2xznb39614nk0m6gs";
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
    license = if unfree then licenses.elastic else licenses.asl20;
    platforms = with platforms; linux;
  };
}
