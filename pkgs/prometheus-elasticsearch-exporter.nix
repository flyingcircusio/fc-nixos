{ stdenv, buildGoPackage, fetchFromGitHub }:

buildGoPackage rec {
  name = "elasticsearch_exporter-${version}";
  version = "1.0.2";
  rev = "v${version}";

  goPackagePath = "github.com/justwatchcom/elasticsearch_exporter";

  src = fetchFromGitHub {
    inherit rev;
    owner = "justwatchcom";
    repo = "elasticsearch_exporter";
    sha256 = "0ms23hqgz5xvzc74ysc5d43v3rvv4hbg6p3zcg84cimfqhg4ilcy";
  };

  # # FIXME: megacli test fails
  # doCheck = false;

  meta = with stdenv.lib; {
    description = "Prometheus exporter for elasticsearch";
    homepage = https://github.com/justwatchcom/elasticsearch_exporter;
    license = licenses.asl20;
    maintainers = with maintainers; [ zagy ];
    platforms = platforms.unix;
  };
}
