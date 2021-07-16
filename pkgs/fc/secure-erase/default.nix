{ lib, stdenv, cryptsetup, bash }:

stdenv.mkDerivation rec {
  version = "0.1";
  name = "fc-secure-erase";

  src = ./secure-erase.sh;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;

  propagatedBuildInputs = [ bash cryptsetup ];

  installPhase = ''
    mkdir -p $out/bin
    cp ${src} $out/bin/fc-secure-erase
    chmod +x $out/bin/fc-secure-erase
  '';

  meta = with lib; {
    description = "fc-secure-erase";
    maintainers = [ maintainers.theuni ];
    platforms = platforms.unix;
  };

}
