{ lib, stdenv, fetchurl, lzo, fuse, autoPatchelfHook }:


stdenv.mkDerivation rec {
  version = "1.0.0";
  name = "restore-single-files-${version}";

  src = null;
  nativeBuildInputs = [
    autoPatchelfHook
  ];

  phases = ["installPhase" "fixupPhase"];

  installPhase = ''
    mkdir -p $out/bin
    cp ${./restore-single-files.sh} $out/bin/restore-single-files
    chmod +x $out/bin/restore-single-files
  '';

  meta = with lib; {
    description = "";
    license = licenses.bsd3;
    maintainers = [ maintainers.ckauhaus ];
    platforms = platforms.unix;
  };

}
