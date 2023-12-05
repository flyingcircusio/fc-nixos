import ./make-test-python.nix ({ rolename ? "percona80", lib, pkgs, testlib, ... }:
let
  master6Fe = testlib.fcIP.fe6 1;
  master6Srv = testlib.fcIP.srv6 1;
  master4Fe = testlib.fcIP.fe4 1;
  master4Srv = testlib.fcIP.srv4 1;

in
{
  name = "mysql-${rolename}";
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
      flyingcircus.roles.mysql.extraConfig = ''
        [mysqld]
        innodb-buffer-pool-size         = 10M
        innodb_log_file_size            = 10M
      '';
    };
  };

  testScript = { nodes, ... }:
  let
    config = nodes.master.config;
    sensuChecks = config.flyingcircus.services.sensu-client.checks;
    mysqlCheck = sensuChecks.mysql.command;
    version = config.services.percona.package.version;
    expectedAddresses = if lib.versionAtLeast version "8.0" then [
      # 8.0 binds to lo and srv with port 3306
      "${master4Srv}:3306"
      "127.0.0.1:3306"
      ":::33060"
      "${master6Srv}:3306"
      "::1:3306"
    ]
    else [
      # older versions listen on all ipv4 interfaces
      "0.0.0.0:3306"
    ];

    expectedAddressesExpr = lib.concatStringsSep " |" expectedAddresses;

  in ''
    start_all()
    master.wait_for_unit("mysql")

    with subtest("generated tmpfiles rules should cause no warnings"):
        # Warnings start with the file name, 00-nixos.conf contains generated tmpfiles rules.
        master.fail("systemd-tmpfiles --clean 2>&1 | grep 00-nixos.conf")

    with subtest("mysql works"):
        master.wait_until_succeeds("mysqladmin ping")

    master.sleep(5)

    with subtest("can login with root password"):
        master.succeed("mysql mysql -u root -p$(< /etc/local/mysql/mysql.passwd) -e 'select 1'")

    with subtest("mysql only opens expected ports"):
        # check for expected ports
        ${lib.concatMapStringsSep
          "\n    "
            (a: ''master.succeed("netstat -tlpn | grep mysqld | grep '${a}'")'')
            expectedAddresses
        }
        # check for unexpected ports
        master.fail("netstat -tlpn | grep mysqld | egrep -v '${expectedAddressesExpr}'")

    with subtest("after logrotate, mysql should write to the new slow log file"):
        master.execute("logrotate -v -f /etc/current-config/logrotate.conf")
        master.succeed("grep select /var/log/mysql/mysql.slow")

    with subtest("slow log should have correct permissions (readable for service users)"):
        master.succeed("stat /var/log/mysql/mysql.slow -c %a:%U:%G | grep '640:mysql:service'")

    with subtest("old slow log file should be compressed"):
        master.succeed("stat /var/log/mysql/mysql.slow.1.gz")

    with subtest("killing the mysql process should trigger an automatic restart"):
        master.succeed("kill -9 $(systemctl show mysql.service --property MainPID --value)")
        master.wait_for_unit("mysql")
        master.wait_until_succeeds("mysqladmin ping")

    with subtest("all sensu checks should be green"):
        master.wait_for_unit("fc-mysql-post-init.service")
        master.succeed("""${mysqlCheck}""")

    with subtest("status check should be red after shutting down mysql"):
        master.succeed('systemctl stop mysql')
        master.fail("""${mysqlCheck}""")

    with subtest("secret files should have correct permissions"):
        master.succeed("stat /etc/local/mysql/mysql.passwd -c %a:%U:%G | grep '660:root:service'")
        master.succeed("stat /root/.my.cnf -c %a:%U:%G | grep '440:root:root'")
        master.succeed("stat /run/mysqld/init_set_root_password.sql -c %a:%U:%G | grep '440:mysql:root'")

    with subtest("root should be able to connect after changing the password"):
        master.succeed("echo tt > /etc/local/mysql/mysql.passwd")
        master.succeed("systemctl restart mysql")
        master.wait_until_succeeds("mysql mysql -u root -ptt -e 'select 1'")

    with subtest("xtrabackup works"): # sensuclient has service group
        master.succeed("sudo -u sensuclient sudo xtrabackup --backup -S /run/mysqld/mysqld.sock")
        master.succeed("grep uuid /tmp/xtrabackup_backupfiles/xtrabackup_info")
  '';

})
