{
  stdenv,
  fetchurl,
  tree,
}:

stdenv.mkDerivation rec {
  version = "2.4.0";
  pname = "kubernetes-dashboard";

  src = fetchurl {
    url = "http://downloads.fcio.net/packages/${pname}-${version}.tar.gz";
    sha256 = "0zwp2c3bj4z89mv5ijcijfqnhqcr12ljlg9rm5qhspbkvny0k1is";
  };

  buildPhase = ":";

  installPhase = ''
    mkdir $out
    cp -r * $out/
  '';
}
