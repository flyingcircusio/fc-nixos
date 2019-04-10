import ./make-test.nix ({ ... }:

# Checks that systemd does not detect any circular service dependencies on boot.
{
  name = "systemd-service-cycles";
  machine =
    { ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
    };

  testScript = ''
    $machine->waitForUnit('multi-user.target');
    $machine->waitUntilSucceeds('pgrep -f "agetty.*tty1"');
    $machine->fail('journalctl -b | egrep "systemd.*cycle"');
  '';
})
