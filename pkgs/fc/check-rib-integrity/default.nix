{ lib, stdenv, makeWrapper, python3, iproute2, frr }:

stdenv.mkDerivation rec {
  version = "1";
  pname = "check-rib-integrity";

  src = ./.;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;
  nativeBuildInputs = [ makeWrapper ];
  propagatedBuildInputs = [ python3 iproute2 frr ];

  installPhase = ''
    mkdir -p $out/bin
    cd $src
    install check_rib_integrity.py $out/bin/check_rib_integrity
    wrapProgram $out/bin/check_rib_integrity --prefix PATH : \
      ${lib.makeBinPath propagatedBuildInputs}
  '';

  meta = with lib; {
    description = "Sensu check for monitoring FRR correctly maintaining the routing information base";
    platforms = platforms.unix;
  };
}
