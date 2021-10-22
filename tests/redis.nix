import ./make-test-python.nix ({ ... }:
{
  name = "redis";
  nodes = {
    redis =
      { ... }:
      {
        imports = [ ../nixos ../nixos/roles ];
        flyingcircus.roles.redis.enable = true;

        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.srv = {
            mac = "52:54:00:12:34:56";
            bridged = false;
            networks = {
              "192.168.1.0/24" = [ "192.168.1.1" ];
            };
            gateways = {};
          };
        };

      };
  };

  testScript = ''
    redis.wait_for_unit("redis.service")
    cli = "redis-cli -a `< /etc/local/redis/password `"
    redis.wait_until_succeeds(f"{cli} ping | grep PONG")
    redis.succeed(f"{cli} set msg 'broken world'")
    redis.succeed(f"{cli} get msg | grep 'hello world'")

    # service user should be able to write the password file
    redis.succeed('sudo -u redis touch /etc/local/redis/password')

    # killing the redis process should trigger an automatic restart
    redis.succeed("kill $(systemctl show redis.service --property MainPID | sed -e 's/MainPID=//')")
    redis.wait_for_unit("redis.service")
    redis.wait_until_succeeds(f"{cli} ping | grep PONG")
  '';
})
