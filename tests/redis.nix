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

          services.redis.servers.socket_no_pw = {
            enable = true;
            unixSocketPerm = 770;
          };

          specialisation.specialserver.configuration = {
            services.redis.servers.foo-bar = {
              enable = true;
              requirePass = "aligator3";
              port = 6380;
            };
          };

          specialisation.withpw.configuration.flyingcircus.services.redis.password = "aligator3";
          specialisation.withpwfile.configuration.services.redis.servers."".requirePassFile =
            lib.mkForce "${pkgs.writeText "pw" "aligator4"}";

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
        config = nodes.redis.system.build.toplevel;

        sensuChecksWithPW =
          nodes.redis.specialisation.withpw.configuration.flyingcircus.services.sensu-client.checks;
      in
      ''
        import json
        import urllib.parse

        def switch_specialisation(name):
            path = "${config}/bin/switch-to-configuration" \
                if name is None \
                else f"${config}/specialisation/{name}/bin/switch-to-configuration"
            redis.succeed(f"{path} test")

        def query_prom(qry):
            str_val = urllib.parse.quote_plus(qry)
            redis.wait_until_succeeds(f"test true = \"$(curl -s ${api}/query?query={str_val} | jq '.data.result|length > 0')\"")

            ret_val = json.loads(redis.succeed(f"""
                curl -s ${api}/query?query={str_val}
            """))
            print(ret_val)

            return ret_val


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

        cli_socket_no_pw = "redis-cli -s /run/redis-socket_no_pw/redis.sock"
        redis.wait_until_succeeds(f"{cli_socket_no_pw} ping | grep PONG")
        redis.wait_until_succeeds(f"{cli_socket_no_pw} set msg 'hello world'")
        redis.wait_until_succeeds(f"{cli_socket_no_pw} get msg | grep 'hello world'")

        with subtest("service user should be able to write the password file"):
            redis.succeed('sudo -u redis touch /etc/local/redis/password')

        with subtest("Sensu checks correctly configured"):
            redis.succeed("${pkgs.writeShellScript "sensu-redis" sensuChecks.redis.command}")
            redis.succeed("${pkgs.writeShellScript "sensu-redis-gitlab" sensuChecks.redis-gitlab.command}")

        with subtest("Metrics for servers are scraped by telegraf"):
            ret_val = query_prom('redis_uptime{port="6379"}')
            t.assertEqual(ret_val['status'], 'success')
            t.assertEqual(len(ret_val['data']['result']), 1)

            ret_val = query_prom('redis_uptime{socket="/run/redis-gitlab/redis.sock"}')
            t.assertEqual(ret_val['status'], 'success')
            t.assertEqual(len(ret_val['data']['result']), 1)

        with subtest("killing the redis process should trigger an automatic restart"):
            redis.succeed("kill $(systemctl show redis.service --property MainPID | sed -e 's/MainPID=//')")
            redis.succeed("sleep 5")
            redis.wait_for_unit("redis.service")
            redis.wait_until_succeeds(f"{cli} ping | grep PONG")

        with subtest("Dashes in server names make no problems"):
            switch_specialisation("specialserver")
            redis.succeed(f"redis-cli -a aligator3 -p 6380 ping | grep PONG")
            ret_val = query_prom('redis_uptime{port="6380"}')

            t.assertEqual(ret_val['status'], 'success')
            data = ret_val['data']['result']
            t.assertEqual(len(ret_val['data']['result']), 1)

        with subtest("/etc/local/redis/password is kept up-to-date"):
            password = redis.succeed("cat /etc/local/redis/password").strip()
            switch_specialisation("withpw")
            from_pw_string = redis.succeed("cat /etc/local/redis/password").strip()

            t.assertNotEqual(password, from_pw_string)
            redis.succeed(f"redis-cli -a {from_pw_string} ping | grep PONG")

            redis.succeed("${pkgs.writeShellScript "sensu-redis" sensuChecksWithPW.redis.command}")
            redis.succeed("${pkgs.writeShellScript "sensu-redis-gitlab" sensuChecksWithPW.redis-gitlab.command}")

            # We don't generate a password if /etc/local/redis/password already
            # exists, even if there are no other settings.
            switch_specialisation(None)
            redis.succeed(f"redis-cli -a {from_pw_string} ping | grep PONG")

            switch_specialisation("withpwfile")
            from_pwfile = redis.succeed("cat /etc/local/redis/password").strip()
            t.assertNotEqual(from_pwfile, from_pw_string)
            redis.succeed(f"redis-cli -a {from_pwfile} ping | grep PONG")
      '';
  }
)
