import ./make-test-python.nix ({ ... }:
{
  name = "prometheus";
  machine =
    { config, ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
      config.services.prometheus.enable = true;

    };
  testScript = ''
    machine.wait_for_unit("prometheus.service")
    machine.sleep(5)

    with subtest("Prometheus should serve its own metrics"):
        machine.succeed("curl 'localhost:9090/metrics' | grep go_goroutines")

    with subtest("Metrics dir should only allow access for prometheus user"):
        machine.succeed("stat /srv/prometheus/metrics -c %a:%U:%G | grep '700:prometheus:prometheus'")
  '';
})
