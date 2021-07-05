import ./make-test-python.nix ({ rolename ? "percona80", lib, pkgs, ... }:
let
  net6Fe = "2001:db8:1::";
  net6Srv = "2001:db8:2::";

  master6Fe = net6Fe + "1";
  master6Srv = net6Srv + "1";

  net4Fe = "10.0.1";
  net4Srv = "10.0.2";

  master4Fe = net4Fe + ".1";
  master4Srv = net4Srv + ".1";

in
{
  name = "mysql-${rolename}";
  nodes = {
    master =
    { pkgs, config, ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
      virtualisation.memorySize = 2048;

      flyingcircus.roles.${rolename}.enable = true;

      # Tune those arguments as we'd like to run this on Hydra
      # in a rather small VM.
      flyingcircus.roles.mysql.extraConfig = ''
        [mysqld]
        innodb-buffer-pool-size         = 10M
        innodb_log_file_size            = 10M
      '';

      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:02:01";
          bridged = false;
          networks = {
            "${net4Srv}.0/24" = [ master4Srv ];
            "${net6Srv}/64" = [ master6Srv ];
          };
          gateways = {};
        };
        interfaces.fe = {
          mac = "52:54:00:12:01:01";
          bridged = false;
          networks = {
            "${net4Fe}.0/24" = [ master4Fe ];
            "${net6Fe}/64" = [ master6Fe ];
          };
          gateways = {};
        };
      };
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
  '';

})
