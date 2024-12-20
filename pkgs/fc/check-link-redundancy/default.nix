{ lib, stdenv, makeWrapper, python3, lldpd }:

stdenv.mkDerivation rec {
  version = "2";
  pname = "check-link-redundancy";

  src = ./.;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;
  nativeBuildInputs = [ makeWrapper ];
  propagatedBuildInputs = [ python3 lldpd ];

  installPhase = ''
    mkdir -p $out/bin
    cd $src
    install check_link_redundancy.py $out/bin/check_link_redundancy
    wrapProgram $out/bin/check_link_redundancy --prefix PATH : \
      ${lib.makeBinPath propagatedBuildInputs}
  '';

  meta = with lib; {
    description = "Sensu check script to ensure that physical interfaces are not connected to the same switch";
    platforms = platforms.unix;
  };
}
