import ./make-test-python.nix ({ ... }:
{
  name = "locale";
  machine =
    { ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
    };

  testScript = ''
    machine.succeed("locale -a | grep -q de_DE.utf8")
    machine.succeed("locale -a | grep -q en_US.utf8")
    machine.succeed('(($(locale -a | wc -l) > 100))')
  '';
})
