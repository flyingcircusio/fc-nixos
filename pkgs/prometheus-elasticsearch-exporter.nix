{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  name = "elasticsearch_exporter-${version}";
  version = "1.9.0";
  rev = "v${version}";

  src = fetchFromGitHub {
    inherit rev;
    owner = "prometheus-community";
    repo = "elasticsearch_exporter";
    sha256 = "sha256-v6Fi5O/87jhFI1h6qWyWb61X+dTjcqS3Fi9/MPQSr8Y=";
  };
  vendorHash = "sha256-NAaVz5AqhfaEiWqBAeQZVWwjMIwX9jEw0oycXq7uLNw=";

  meta = with lib; {
    description = "Prometheus exporter for elasticsearch";
    homepage = "https://github.com/prometheus-community/elasticsearch_exporter";
    license = licenses.asl20;
    maintainers = with maintainers; [ zagy ];
    platforms = platforms.unix;
  };
}
