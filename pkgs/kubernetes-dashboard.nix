{ stdenv, fetchurl, tree }:

stdenv.mkDerivation rec {
  version = "2.0.4";
  pname = "kubernetes-dashboard";

  src = fetchurl {
    url = "http://downloads.fcio.net/packages/${pname}-${version}.tar.gz";
    sha256 = "0z3fpqh6p9mwj44k213qp5whsa42hz1whaqjfwd2rrdc1yfyz9p5";
  };

  buildPhase = ":";

  installPhase = ''
    mkdir $out
    cp -r * $out/
  '';
}
