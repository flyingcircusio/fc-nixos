{ stdenv, fetchurl, erlang, python, libxml2, libxslt, xmlto
, docbook_xml_dtd_45, docbook_xsl, zip, unzip, rsync }:

stdenv.mkDerivation rec {
  name = "rabbitmq-server-${version}";

  version = "3.6.5";

  src = fetchurl {
    url = "http://www.rabbitmq.com/releases/rabbitmq-server/v${version}/${name}.tar.xz";
    sha256 = "1v48ay4z8n9q9c8rg7fhrfa4cg2dqiwbjnr3yl5i7xdam0y46l4m";
  };

  buildInputs =
    [ erlang python libxml2 libxslt xmlto docbook_xml_dtd_45 docbook_xsl zip unzip rsync ];

  preBuild =
    ''
      # Fix the "/usr/bin/env" in "calculate-relative".
      patchShebangs .
    '';

  installFlags = "PREFIX=$(out) RMQ_ERLAPP_DIR=$(out)";

  preInstall =
    ''
      sed -i \
        -e 's|SYS_PREFIX=|SYS_PREFIX=''${SYS_PREFIX-''${HOME}/.rabbitmq/${version}}|' \
        -e 's|CONF_ENV_FILE=''${SYS_PREFIX}\(.*\)|CONF_ENV_FILE=\1|' \
        scripts/rabbitmq-defaults
    '';

  postInstall =
    ''
      echo 'PATH=${erlang}/bin:${PATH:+:}$PATH' >> $out/sbin/rabbitmq-env
    '';

  meta = {
    homepage = http://www.rabbitmq.com/;
    description = "An implementation of the AMQP messaging protocol";
    platforms = stdenv.lib.platforms.unix;
  };
}
