{ lib, stdenv, bash, gawk, dmidecode, megacli, utillinux, makeWrapper }:


stdenv.mkDerivation rec {
  version = "0.1";
  name = "check_megaraid";

  src = ./check_megaraid.sh;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;

  buildInputs = [ makeWrapper ];
  propagatedBuildInputs = [ bash dmidecode gawk megacli utillinux ];

  installPhase = ''
    install -D -m 755 $src $out/bin/.check_megaraid
    makeWrapper $out/bin/.check_megaraid $out/bin/check_megaraid \
      --prefix PATH : ${lib.makeBinPath propagatedBuildInputs}

  '';

  meta = with lib; {
    description = "check_megaraid";
    maintainers = [ maintainers.theuni ];
    homepage = "https://github.com/onnozweers/Nagios-plugins/blob/master/check_megaraid";
    platforms = platforms.unix;
  };

}
