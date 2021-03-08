{ lib, stdenv, fetchurl, perl, freeipmi, makeWrapper, perlPackages }:

stdenv.mkDerivation rec {
  version = "3.13";
  name = "check_ipmi_sensor-${version}";

  src = fetchurl {
    url = "https://github.com/thomas-krenn/check_ipmi_sensor_v3/archive/v${version}.tar.gz";
    sha256 = "1a7n2ri5pb8v2w91al4gz5fv4gr4788w2sjy58yznq7yf9cdd9q3";
  };

  propagatedBuildInputs = [ freeipmi ];
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin

    substituteInPlace check_ipmi_sensor \
      --replace "/usr/bin/perl" "${perl}/bin/perl" \
      --replace "/usr/sbin/ipmimonitoring" "${freeipmi}/bin/ipmimonitoring" \
      --replace "/usr/sbin/ipmi-sel" "${freeipmi}/bin/ipmi-sel" \
      --replace "/usr/sbin/ipmi-dcmi" "${freeipmi}/bin/ipmi-dcmi"
    cp -a check_ipmi_sensor $out/bin/
    wrapProgram $out/bin/check_ipmi_sensor \
      --prefix PERL5LIB : "${perlPackages.makePerlPath [ perlPackages.IPCRun ]}"

    chmod +x $out/bin/*
  '';

  meta = with lib; {
    description = "Monitoring plugin to check IPMI sensors";
    homepage = "https://www.thomas-krenn.com/en/wiki/IPMI_Sensor_Monitoring_Plugin";
    license = licenses.gpl3;
    maintainers = [ maintainers.theuni ];
    platforms = platforms.unix;
  };

}
