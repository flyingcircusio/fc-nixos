{
  lib,
  stdenv,
  makeWrapper,
  python3,
  iproute2,
}:

stdenv.mkDerivation rec {
  version = "1";
  pname = "check-vrf-pub-default-routes";

  src = ./.;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;
  nativeBuildInputs = [ makeWrapper ];
  propagatedBuildInputs = [
    python3
    iproute2
  ];

  installPhase = ''
    mkdir -p $out/bin
    cd $src
    install check_vrf_pub_default_routes.py $out/bin/check_vrf_pub_default_routes
    wrapProgram $out/bin/check_vrf_pub_default_routes --prefix PATH : \
      ${lib.makeBinPath propagatedBuildInputs}
  '';

  meta = with lib; {
    description = "Sensu check for monitoring VRF pub default routes";
    platforms = platforms.unix;
  };
}
