{
  lib,
  stdenv,
  python312,
  megacli,
  lvm2,
  makeWrapper,
}:

stdenv.mkDerivation rec {
  version = "0.1";
  name = "fc-install";

  src = ./fc-install.py;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;

  buildInputs = [ python312 ];

  installPhase = ''
    mkdir -p $out/bin
    cp ${src} $out/bin/fc-install
    chmod +x $out/bin/fc-install
    patchShebangs $out/bin
  '';

  meta = with lib; {
    description = "fc-install";
    maintainers = [ maintainers.theuni ];
    platforms = platforms.unix;
  };

}
