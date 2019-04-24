import ./make-test.nix ({ ... }:
{
  name = "prometheus";
  machine =
    { config, ... }:
    {
      imports = [ ../nixos ];
      config.services.prometheus2.enable = true;
    };
  testScript = ''
    $machine->waitForUnit("prometheus2.service");
    $machine->sleep(5);
    $machine->succeed("curl 'localhost:9090/metrics' | grep go_goroutines");
  '';
})
