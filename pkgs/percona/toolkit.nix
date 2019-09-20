{ buildPerlPackage, fetchurl, perlPackages, }:
with perlPackages;

buildPerlPackage rec {
  name = "percona-toolkit-${version}";
  version = "3.0.8";

  src = fetchurl {
    url = "https://www.percona.com/downloads/percona-toolkit/${version}/binary/tarball/percona-toolkit-${version}_x86_64.tar.gz";
    sha256 = "73aa2a77d58f8f3584f930ea587f24c79c506d73db015bf0c6aebe3d541feae6";
  };

  propagatedBuildInputs = [
    DBDmysql
    TimeHiRes
  ];
}
