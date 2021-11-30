{ stdenv, fetchurl, tree }:

stdenv.mkDerivation rec {
  version = "1.0.7";
  pname = "kubernetes-dashboard-metrics-scraper";

  src = fetchurl {
    url = "http://downloads.fcio.net/packages/${pname}-${version}.tar.gz";
    sha256 = "0sqlgp6869idl50dsl9w7vw4z01l5z5bqk6a132ngpcvc4p3c3sd";
  };

  buildPhase = ":";

  installPhase = ''
    mkdir $out
    cp -r * $out/
  '';
}
