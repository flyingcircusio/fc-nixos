{ lib, stdenv, python3Full, ipmitool, makeWrapper }:


stdenv.mkDerivation rec {
  version = "0.1";
  name = "fc-ipmitool";

  src = ./fc-ipmitool.py;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python3Full ];

  installPhase = ''
    mkdir -p $out/bin
    cp ${src} $out/bin/fc-ipmitool
    chmod +x $out/bin/fc-ipmitool
    patchShebangs $out/bin
    wrapProgram $out/bin/fc-ipmitool \
      --prefix PATH : "${lib.makeBinPath [ ipmitool ]}"
  '';

  meta = with lib; {
    description = "fc-ipmitool";
    maintainers = [ maintainers.theuni ];
    platforms = platforms.unix;
  };

}
