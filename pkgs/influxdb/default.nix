{ lib, buildGoPackage, fetchFromGitHub, }:

buildGoPackage rec {
  name = "influxdb-${version}";
  version = "1.6.6";

  src = fetchFromGitHub {
    owner = "influxdata";
    repo = "influxdb";
    rev = "v${version}";
    sha256 = "05b27hq49mjgiqs5nsa67lffgrzqsk0b3kys34l2i0djpda8ld3l";
  };

  buildFlagsArray = [ ''-ldflags=
    -X main.version=${version}
  '' ];

  goPackagePath = "github.com/influxdata/influxdb";

  excludedPackages = "test";

  # Generated with the nix2go
  goDeps = ./. + builtins.toPath "/deps-${version}.nix";

  meta = with lib; {
    description = "An open-source distributed time series database";
    license = licenses.mit;
    homepage = https://influxdb.com/;
    maintainers = with maintainers; [ offline zimbatm ];
    platforms = platforms.linux;
  };
}
