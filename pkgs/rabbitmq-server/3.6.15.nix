{ stdenv, fetchurl, erlang, python, libxml2, libxslt, xmlto
, docbook_xml_dtd_45, docbook_xsl, zip, unzip, rsync, getconf
}:

stdenv.mkDerivation rec {
  name = "rabbitmq-server-${version}";

  version = "3.6.15";

  src = fetchurl {
    url = "https://www.rabbitmq.com/releases/rabbitmq-server/v${version}/${name}.tar.xz";
    sha256 = "1zdmil657mhjmd20jv47s5dfpj2liqwvyg0zv2ky3akanfpgj98y";
  };

  buildInputs =
    [ erlang python libxml2 libxslt xmlto docbook_xml_dtd_45 docbook_xsl zip unzip rsync getconf];

  preBuild =
    ''
      # Fix the "/usr/bin/env" in "calculate-relative".
      patchShebangs .
    '';

  installFlags = "PREFIX=$(out) RMQ_ERLAPP_DIR=$(out)";
  installTargets = "install install-man";

  postInstall =
    ''
      echo 'PATH=${getconf}/bin:${erlang}/bin:''${PATH:+:}$PATH' >> $out/sbin/rabbitmq-env
    '';

  meta = {
    homepage = http://www.rabbitmq.com/;
    description = "An implementation of the AMQP messaging protocol";
    platforms = stdenv.lib.platforms.unix;
  };
}
