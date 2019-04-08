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
    $machine->succeed("curl 'localhost:9090/metrics' | grep go_goroutines");
  '';
})
