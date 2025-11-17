{
  lib,
  stdenv,
  makeWrapper,
  python3,
}:

stdenv.mkDerivation rec {
  version = "1";
  pname = "check-skvaider";

  src = ./.;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;
  nativeBuildInputs = [ makeWrapper ];
  propagatedBuildInputs = [
    (python3.withPackages (python-pkgs: [
      python-pkgs.requests
    ]))
  ];

  installPhase = ''
    mkdir -p $out/bin
    cd $src
    install check_skvaider.py $out/bin/check_skvaider
    wrapProgram $out/bin/check_skvaider --prefix PATH : \
      ${lib.makeBinPath propagatedBuildInputs}
  '';

  meta = with lib; {
    description = "Sensu check for skvaider functionality";
    platforms = platforms.unix;
  };
}
