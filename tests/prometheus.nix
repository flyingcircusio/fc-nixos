import ./make-test.nix ({ ... }:
{
  name = "prometheus";
  machine =
    { config, ... }:
    {
      imports = [ ../nixos ];
      config.services.prometheus.enable = true;
    };
  testScript = ''
    $machine->waitForUnit("prometheus.service");
    $machine->sleep(5);

    subtest "Prometheus should serve its own metrics", sub {
      $machine->succeed("curl 'localhost:9090/metrics' | grep go_goroutines");
    };

    subtest "Metrics dir should only allow access for prometheus user", sub {
      $machine->succeed("stat /srv/prometheus/metrics -c %a:%U:%G | grep '700:prometheus:prometheus'");
    };
  '';
})
