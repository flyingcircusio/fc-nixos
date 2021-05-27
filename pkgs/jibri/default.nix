{ pkgs, lib, stdenv, fetchurl, dpkg, jre_headless, chromium, chromedriver, ffmpeg, curl }:

let
  jibriPkgs = with pkgs; [
    chromium
    chromedriver
    ffmpeg
    curl
    procps
  ];
in
stdenv.mkDerivation rec {
  pname = "jibri";
  version = "8.0-83-g204354d";
  src = fetchurl {
    url = "https://download.jitsi.org/stable/${pname}_${version}-1_all.deb";
    sha256 = "0407zfd14y9l1021l3fqs3qnlvq2j7prsf8dzfhj9gnkrshb7cnn";
  };
  dontBuild = true;
  buildInputs = [ pkgs.makeWrapper ];
  unpackCmd = "${dpkg}/bin/dpkg-deb -x $src debcontents";

  installPhase = ''
    mkdir -p $out/bin
    mv opt $out/
    mv etc $out/
    cp ${./logging.properties-journal} $out/etc/jitsi/jibri/logging.properties-journal

    cat > $out/bin/jibri << __EOF__
    export PATH='${lib.makeBinPath jibriPkgs}:$PATH'
    exec ${jre_headless}/bin/java -Djava.util.logging.config.file=\$JIBRI_LOGGING_CONFIG_FILE -Dconfig.file=\$JIBRI_CONFIG_FILE -jar $out/opt/jitsi/jibri/jibri.jar "\$@"
    __EOF__

    chmod +x $out/bin/jibri
  '';

  meta = with lib; {
    description = "JItsi BRoadcasting Infrastructure";
    homepage = "https://github.com/jitsi/jibri";
    license = licenses.asl20;
    maintainers = lib.teams.jitsi.members;
    platforms = platforms.linux;
  };
}
