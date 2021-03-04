{ lib, stdenv, python3Full, megacli, lvm2 }:


stdenv.mkDerivation rec {
  version = "0.1";
  name = "fc-blockdev";

  src = ./fc-blockdev.py;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;

  buildInputs = [ python3Full ];
  propagatedBuildInputs = [ lvm2 ];

  installPhase = ''
    mkdir -p $out/bin
    cp ${src} $out/bin/fc-blockdev
    chmod +x $out/bin/fc-blockdev
    patchShebangs $out/bin
  '';

  meta = with lib; {
    description = "fc-blockdev";
    maintainers = [ maintainers.theuni ];
    platforms = platforms.unix;
  };

}
