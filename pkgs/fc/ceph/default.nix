{ lib, stdenv, python3Full, blockdev, lvm2 }:


stdenv.mkDerivation rec {
  version = "0.1";
  name = "fc-ceph";

  src = ./fc-ceph.py;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;

  buildInputs = [ python3Full blockdev ];
  propagatedBuildInputs = [ lvm2 ];

  installPhase = ''
    mkdir -p $out/bin
    cp ${src} $out/bin/fc-ceph
    chmod +x $out/bin/fc-ceph
    patchShebangs $out/bin
  '';

  meta = with lib; {
    description = "fc-ceph";
    maintainers = [ maintainers.theuni ];
    platforms = platforms.unix;
  };

}
