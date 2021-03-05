{ lib, stdenv, gawk, bash }:


stdenv.mkDerivation rec {
  version = "0.1";
  name = "check_md_raid";

  src = ./check_md_raid.sh;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;

  propagatedBuildInputs = [ bash gawk ];

  installPhase = ''
    mkdir -p $out/bin
    cp ${src} $out/bin/check_md_raid
    chmod +x $out/bin/check_md_raid
  '';

  meta = with lib; {
    description = "check_md_raid";
    maintainers = [ maintainers.theuni ];
    homepage = "https://exchange.nagios.org/directory/Plugins/Operating-Systems/Linux/check_md_raid/details";
    platforms = platforms.unix;
  };

}
