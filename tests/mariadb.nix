import ./make-test-python.nix (
  {
    rolename ? "mariadb114",
    lib,
    pkgs,
    testlib,
    ...
  }:
  let
    master6Fe = testlib.fcIP.fe6 1;
    master6Srv = testlib.fcIP.srv6 1;
    master4Fe = testlib.fcIP.fe4 1;
    master4Srv = testlib.fcIP.srv4 1;

  in
  {
    name = "mariadb-${rolename}";
    nodes = {
      master =
        { pkgs, config, ... }:
        {
          imports = [
            (testlib.fcConfig { })
          ];
          virtualisation.memorySize = 2048;

          flyingcircus.roles.${rolename}.enable = true;

          # Tune those arguments as we'd like to run this on Hydra
          # in a rather small VM.
          services.mysql.settings.mysqld = {
            innodb-buffer-pool-size = lib.mkForce "10M";
            innodb_log_file_size = lib.mkForce "10M";
          };
        };
    };

    testScript =
      { nodes, ... }:
      let
        config = nodes.master;
        sensuChecks = config.flyingcircus.services.sensu-client.checks;
        mariadbCheck = "sudo -u sensuclient " + sensuChecks.mariadb.command;
        expectedAddresses = [
          # 8.0 binds to lo and srv with port 3306
          "${master4Srv}:3306"
          "127.0.0.1:3306"
          "[${master6Srv}]:3306"
          "[::1]:3306"
        ];
      in
      ''
        def assert_listen(machine, process_name, expected_sockets):
          result = machine.succeed(f"ss -tlpn | grep {process_name} | awk '{{ print $4 }}'")
          actual = set(result.splitlines())
          assert expected_sockets == actual, f"expected sockets: {expected_sockets}, found: {actual}"

        start_all()
        master.wait_for_unit("mysql")

        with subtest("generated tmpfiles rules should cause no warnings"):
            # Warnings start with the file name, 00-nixos.conf contains generated tmpfiles rules.
            master.fail("systemd-tmpfiles --clean 2>&1 | grep 00-nixos.conf")

        with subtest("mariadb works"):
            master.wait_until_succeeds("mysqladmin ping")

        master.sleep(5)

        with subtest("can connect as user mariadb"):
            master.succeed("sudo -u mariadb mariadb -e 'select 1'")
            master.succeed("mariadb -e 'select 1'")

        with subtest("mariadb only opens expected ports"):
            # check for expected ports
            assert_listen(master, "mysql", {${
              lib.concatMapStringsSep ", " (x: "\"${x}\"") expectedAddresses
            }})

        with subtest("after logrotate, mariadb should write to the new slow log file"):
            master.execute("logrotate -v -f /etc/current-config/logrotate.conf")
            master.sleep(5)
            master.succeed("grep select /var/log/mariadb/mariadb.slow")

        with subtest("slow log should have correct permissions (readable for service users)"):
            master.succeed("stat /var/log/mariadb/mariadb.slow -c %a:%U:%G | grep '640:mariadb:service'")

        with subtest("old slow log file should be compressed"):
            master.succeed("stat /var/log/mariadb/mariadb.slow.1.gz")

        with subtest("killing the mariadb process should trigger an automatic restart"):
            master.succeed("kill -9 $(systemctl show mysql.service --property MainPID --value)")
            master.wait_for_unit("mysql")
            master.wait_until_succeeds("mysqladmin ping")

        with subtest("creating user and connecting on port works"):
            master.succeed("mariadb -e \"create user test@127.0.0.1 identified by 'foobar' \"")
            master.succeed("mariadb -h 127.0.0.1 -u test -pfoobar -e 'select 1'")

        with subtest("all sensu checks should be green"):
            master.wait_for_unit("mysql.service")
            master.succeed("""${mariadbCheck}""")

        with subtest("status check should be red after shutting down mariadb"):
            master.succeed('systemctl stop mysql')
            master.fail("""${mariadbCheck}""")
      '';
  }
)
