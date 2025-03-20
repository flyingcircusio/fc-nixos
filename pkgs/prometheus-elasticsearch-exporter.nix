{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  name = "elasticsearch_exporter-${version}";
  version = "1.8.0";
  rev = "v${version}";

  src = fetchFromGitHub {
    inherit rev;
    owner = "prometheus-community";
    repo = "elasticsearch_exporter";
    sha256 = "sha256-8WPDBlp6ftBmY/lu0wuuvs3A9KAzEM/A6RqSvYYLm7w=";
  };
  vendorHash = "sha256-jbPFxwrXWwxPamMnbBxFvGBrt38YG7N5fTweAYULEYQ=";

  # # FIXME: megacli test fails
  # doCheck = false;

  meta = with lib; {
    description = "Prometheus exporter for elasticsearch";
    homepage = "https://github.com/prometheus-community/elasticsearch_exporter";
    license = licenses.asl20;
    maintainers = with maintainers; [ zagy ];
    platforms = platforms.unix;
  };
}
