{ lib, stdenv, makeWrapper, python3, iproute2, procps }:

stdenv.mkDerivation rec {
  version = "1";
  pname = "neighbour-cache-monitor";

  src = ./.;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;
  nativeBuildInputs = [ makeWrapper ];
  propagatedBuildInputs = [ python3 iproute2 procps ];

  installPhase = ''
    mkdir -p $out/bin
    cd $src
    install neighbour-cache-monitor.py $out/bin/neighbour-cache-monitor
    wrapProgram $out/bin/neighbour-cache-monitor --prefix PATH : \
      ${lib.makeBinPath propagatedBuildInputs}
  '';

  meta = with lib; {
    description = "Script for monitoring and metrics of kernel neighbour table";
    platforms = platforms.unix;
  };
}
