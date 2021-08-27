{ lib, stdenv, gawk, gnugrep, makeWrapper, bash }:


stdenv.mkDerivation rec {
  version = "0.1";
  name = "check_md_raid";

  src = ./check_md_raid.sh;
  unpackPhase = ":";
  dontBuild = true;
  dontConfigure = true;

  propagatedBuildInputs = [ bash gawk ];
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp ${src} $out/bin/check_md_raid
    chmod +x $out/bin/check_md_raid
    wrapProgram $out/bin/check_md_raid \
      --set PATH "${lib.makeBinPath [ gnugrep bash gawk ]}"
  '';

  meta = with lib; {
    description = "check_md_raid";
    maintainers = [ maintainers.theuni ];
    homepage = "https://exchange.nagios.org/directory/Plugins/Operating-Systems/Linux/check_md_raid/details";
    platforms = platforms.unix;
  };

}
