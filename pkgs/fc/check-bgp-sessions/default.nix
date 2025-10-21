{
  lib,
  stdenv,
  makeWrapper,
  python3,
  frr,
}:

stdenv.mkDerivation rec {
  version = "1";
  pname = "check-bgp-sessions";

  src = ./.;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;
  nativeBuildInputs = [ makeWrapper ];
  propagatedBuildInputs = [
    python3
    frr
  ];

  installPhase = ''
    mkdir -p $out/bin
    cd $src
    install check_bgp_sessions.py $out/bin/check_bgp_sessions
    wrapProgram $out/bin/check_bgp_sessions --prefix PATH : \
      ${lib.makeBinPath propagatedBuildInputs}
  '';

  meta = with lib; {
    description = "Sensu check for checking BGP session state";
    platforms = platforms.unix;
  };
}
