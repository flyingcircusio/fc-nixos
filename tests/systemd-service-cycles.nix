import ./make-test-python.nix ({ ... }:

# Checks that systemd does not detect any circular service dependencies on boot.
{
  name = "systemd-service-cycles";
  machine =
    { ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
    };

  testScript = ''
    machine.wait_for_unit('multi-user.target')
    machine.wait_until_succeeds('pgrep -f "agetty.*tty1"')
    machine.fail('journalctl -b | egrep "systemd.*cycle"')
  '';
})
