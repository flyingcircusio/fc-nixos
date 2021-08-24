{ lib, stdenv, python3Full, megacli, lvm2, makeWrapper }:


stdenv.mkDerivation rec {
  version = "0.1";
  name = "fc-blockdev";

  src = ./fc-blockdev.py;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python3Full ];

  installPhase = ''
    mkdir -p $out/bin
    cp ${src} $out/bin/fc-blockdev
    chmod +x $out/bin/fc-blockdev
    patchShebangs $out/bin
    wrapProgram $out/bin/fc-blockdev \
      --prefix PATH : "${lib.makeBinPath [ lvm2 megacli ]}"
  '';

  meta = with lib; {
    description = "fc-blockdev";
    maintainers = [ maintainers.theuni ];
    platforms = platforms.unix;
  };

}
