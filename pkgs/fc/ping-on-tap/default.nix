{ lib, stdenv, makeWrapper, python3 }:

let
  pythonWithPackages = python3.withPackages (ps: [ ps.scapy ]);
in
stdenv.mkDerivation rec {
  version = "1";
  pname = "ping-on-tap";

  src = ./.;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;
  nativeBuildInputs = [ makeWrapper ];
  propagatedBuildInputs = [ pythonWithPackages ];

  installPhase = ''
    mkdir -p $out/bin
    cd $src
    install ping-on-tap.py $out/bin/ping-on-tap
    wrapProgram $out/bin/ping-on-tap --prefix PATH : \
      ${lib.makeBinPath propagatedBuildInputs}
  '';

  meta = with lib; {
    description = "Helper script to respond to arp and ping on a tap interface";
    platforms = platforms.unix;
  };
}
