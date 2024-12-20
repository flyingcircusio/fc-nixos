{ lib, stdenv, makeWrapper, python3, iproute2 }:

stdenv.mkDerivation rec {
  version = "1";
  pname = "fc-telegraf-routes-summary";

  src = ./.;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;
  nativeBuildInputs = [ makeWrapper ];
  propagatedBuildInputs = [ python3 iproute2 ];

  installPhase = ''
    mkdir -p $out/bin
    cd $src
    install telegraf-routes-summary.py $out/bin/telegraf-routes-summary
    wrapProgram $out/bin/telegraf-routes-summary --prefix PATH : \
      ${lib.makeBinPath propagatedBuildInputs}
  '';

  meta = with lib; {
    description = "Script for generating Telegraf metrics based on IP routes";
    platforms = platforms.unix;
  };
}
