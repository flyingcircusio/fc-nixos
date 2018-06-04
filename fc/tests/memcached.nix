let nixpkgs = import ../../nixpkgs.nix {};
in import "${nixpkgs}/nixos/tests/make-test.nix" ({ ... }:
{
  name = "memcached";

  nodes = {
    m =
    { pkgs, ... }:
    {
      imports = [
        ../modules/platform
      ];
      config = {
        services.memcached.enable = true;
      };
    };
  };

  testScript = ''
    startAll;
    $m->waitForUnit('memcached');

    $m->succeed(<<'__SHELL__');
    set -e
    echo -e 'add my_key 0 60 11\r\nhello world\r\nquit' | nc localhost 11211 | \
      grep STORED
    echo -e 'get my_key\r\nquit' | nc localhost 11211 | grep 'hello world'
    __SHELL__
  '';
})
