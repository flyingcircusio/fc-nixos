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

    # service user should be able to local config dir
    $redis->succeed('sudo -u redis touch /etc/local/redis/custom.conf');

    # service user should be able to write the password file
    $redis->succeed('sudo -u redis touch /etc/local/redis/password');

    # killing the redis process should trigger an automatic restart
    $redis->succeed("kill \$(systemctl show redis.service --property MainPID | sed -e 's/MainPID=//')");
    $redis->waitForUnit("redis.service");
    $redis->waitUntilSucceeds("$cli ping | grep PONG");

  '';
})
