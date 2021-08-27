{ lib, stdenv, fetchurl, lzo, fuse, autoPatchelfHook }:


stdenv.mkDerivation rec {
  version = "1.0.0";
  name = "backy-extract-${version}";

  src = fetchurl {
    url = "https://github.com/flyingcircusio/backy-extract/releases/download/${version}/${name}.tar.gz";
    sha256 = "04bjy1plcw8bbp0mn9m9g7kxg71qlpi385w6zzs5iafxixjh93l5";
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
