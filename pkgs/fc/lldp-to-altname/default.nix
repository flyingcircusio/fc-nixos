{ lib, stdenv, makeWrapper, python3, lldpd, iproute2 }:

stdenv.mkDerivation rec {
  version = "1";
  pname = "fc-lldp-to-altname";

  src = ./.;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;
  nativeBuildInputs = [ makeWrapper ];
  propagatedBuildInputs = [ python3 lldpd iproute2 ];

  installPhase = ''
    mkdir -p $out/bin
    cd $src
    install fc-lldp-to-altname.py $out/bin/fc-lldp-to-altname
    wrapProgram $out/bin/fc-lldp-to-altname --prefix PATH : \
      ${lib.makeBinPath propagatedBuildInputs}
  '';

  meta = with lib; {
    description = "Script to assign interface altnames based on LLDP information";
    platforms = platforms.unix;
  };
}
