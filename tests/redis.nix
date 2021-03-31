import ./make-test-python.nix ({ ... }:
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
    redis.wait_for_unit("redis.service")
    cli = "redis-cli -a `< /etc/local/redis/password `"
    redis.wait_until_succeeds(f"{cli} ping | grep PONG")
    redis.succeed(f"{cli} set msg 'hello world'")
    redis.succeed(f"{cli} get msg | grep 'hello world'")

    # service user should be able to local config dir
    redis.succeed('sudo -u redis touch /etc/local/redis/custom.conf')

    # service user should be able to write the password file
    redis.succeed('sudo -u redis touch /etc/local/redis/password')

    # killing the redis process should trigger an automatic restart
    redis.succeed("kill $(systemctl show redis.service --property MainPID | sed -e 's/MainPID=//')")
    redis.wait_for_unit("redis.service")
    redis.wait_until_succeeds(f"{cli} ping | grep PONG")
  '';
})
