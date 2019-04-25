import ./make-test.nix ({ ... }:
{
  name = "redis";
  nodes = {
    redis =
      { ... }:
      {
        imports = [ ../nixos ../nixos/roles ];
        flyingcircus.roles.redis.enable = true;
      };
  };

  testScript = ''
    $redis->waitForUnit("redis.service");
    my $cli = "redis-cli -a `< /etc/local/redis/password `";
    $redis->waitUntilSucceeds("$cli ping | grep PONG");
    $redis->succeed("$cli set msg 'hello world'");
    $redis->succeed("$cli get msg | grep 'hello world'");
  '';
})
