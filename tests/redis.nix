import ./make-test-python.nix (
  { pkgs, ... }:
  {
    name = "redis";
    nodes = {
      redis =
        { pkgs, lib, ... }:
        {
          imports = [
            ../nixos
            ../nixos/roles
          ];
          flyingcircus.roles.redis.enable = true;

          services.redis.servers.gitlab = {
            enable = true;
            unixSocketPerm = 770;
            requirePassFile = "${pkgs.writeText "password" "hunter2"}";
          };

          flyingcircus.enc.parameters = {
            resource_group = "test";
            interfaces.srv = {
              mac = "52:54:00:12:34:56";
              bridged = false;
              networks = {
                "192.168.1.0/24" = [ "192.168.1.1" ];
              };
              gateways = { };
            };
          };

          # Taken from statshost-master test: needed to verify that
          # telegraf is correctly configured.
          flyingcircus.roles.statshost-master.enable = true;
          flyingcircus.roles.statshost = {
            hostName = "redis";
            useSSL = false;
          };

          flyingcircus.encAddresses = [
            {
              name = "redis";
              ip = "192.168.1.1";
            }
          ];
          networking.extraHosts = ''
            192.168.1.1 redis.fcio.net redis
          '';

          services.telegraf.enable = true;
          services.telegraf.extraConfig.agent.interval = "1s";

          users.users.s-test = {
            isNormalUser = true;
            extraGroups = [ "service" ];
          };

          services.prometheus.globalConfig.scrape_interval = "1s";

          # Grafana is being enabled by statshost-master. This isn't needed for this
          # test-case and spams the logs, so it's disabled here.
          services.grafana.enable = lib.mkForce false;
        };
    };

    testScript =
      { nodes, ... }:
      let
        sensuChecks = nodes.redis.flyingcircus.services.sensu-client.checks;
        api = "http://192.168.1.1:9090/api/v1";
      in
      ''
        import json

        redis.wait_for_unit("redis.service")
        redis.wait_for_unit("redis-gitlab.service")
        redis.wait_for_unit("prometheus.service")
        redis.wait_for_unit("telegraf.service")
        redis.wait_for_file("/run/telegraf/influx.sock")

        cli = "redis-cli -a `< /etc/local/redis/password `"
        redis.wait_until_succeeds(f"{cli} ping | grep PONG")
        redis.succeed(f"{cli} set msg 'hello world'")
        redis.succeed(f"{cli} get msg | grep 'hello world'")

        cli_gitlab = "redis-cli -a hunter2 -s /run/redis-gitlab/redis.sock"
        redis.wait_until_succeeds(f"{cli_gitlab} ping | grep PONG")
        redis.wait_until_succeeds(f"{cli_gitlab} set msg 'hello world'")
        redis.wait_until_succeeds(f"{cli_gitlab} get msg | grep 'hello world'")

        with subtest("service user should be able to write the password file"):
            redis.succeed('sudo -u redis touch /etc/local/redis/password')

        with subtest("Sensu checks correctly configured"):
            redis.succeed("${pkgs.writeShellScript "sensu-redis" sensuChecks.redis.command}")
            redis.succeed("${pkgs.writeShellScript "sensu-redis-gitlab" sensuChecks.redis-gitlab.command}")

        with subtest("Metrics for servers are scraped by telegraf"):
            redis.wait_until_succeeds("test true = \"$(curl -s ${api}/query?query='redis_uptime' | jq '.data.result|length > 0')\"")

            ret_val = json.loads(redis.succeed("""
                curl -s ${api}/query?query='redis_uptime'
            """))
            print(ret_val)

            assert ret_val['status'] == 'success'
            data = ret_val['data']['result']
            assert len(data) == 2

            assert '/run/redis-gitlab/redis.sock' ==  [x['metric']['socket'] for x in data if 'socket' in x['metric']][0]
            assert '127.0.0.1:6379' ==  [
                x['metric']['server'] + ":" + x['metric']['port']
                for x in data if 'server' in x['metric']
            ][0]

        with subtest("killing the redis process should trigger an automatic restart"):
            redis.succeed("kill $(systemctl show redis.service --property MainPID | sed -e 's/MainPID=//')")
            redis.succeed("sleep 5")
            redis.wait_for_unit("redis.service")
            redis.wait_until_succeeds(f"{cli} ping | grep PONG")
      '';
  }
)
