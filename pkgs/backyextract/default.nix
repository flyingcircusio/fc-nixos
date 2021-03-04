{ lib, stdenv, fetchurl, lzo, fuse, autoPatchelfHook }:


stdenv.mkDerivation rec {
  version = "0.3.1";
  name = "backy-extract-${version}";

  src = fetchurl {
    url = "https://github.com/flyingcircusio/backy-extract/releases/download/${version}/${name}.tar.gz";
    sha256 = "09qzymd704qwbshg8vrj0glw5zwwqbp8lqh1mwmdvm7krmfbldan";
  };

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  buildInputs = [ lzo fuse ];

  installPhase = ''
    mkdir $out
    cp -a bin $out/
    cp ${./restore-single-files.sh} $out/bin/restore-single-files
    chmod +x $out/bin/restore-single-files
    cp -a share $out/
  '';

  meta = with lib; {
    description = "Rapid restore tool for backy";
    license = licenses.bsd3;
    maintainers = [ maintainers.ckauhaus ];
    platforms = platforms.unix;
  };

}
