import ../make-test-python.nix ({ version ? "14", lib, testlib, pkgs, ... }:
let
  ipv4 = testlib.fcIP.srv4 1;
  ipv6 = testlib.fcIP.srv6 1;
in {
  name = "postgresql${version}";
  nodes = {
    machine = { ... }: {
      imports = [
        (testlib.fcConfig { net.fe = false; })
      ];

      flyingcircus.roles."postgresql${version}".enable = true;
    };
  };

  testScript =
  { nodes, ... }:
    let
      insertSql = pkgs.writeText "insert.sql" ''
        CREATE TABLE employee (
          id INT PRIMARY KEY,
          name TEXT
        );
        INSERT INTO employee VALUES (1, 'John Doe');
      '';

      selectSql = pkgs.writeText "select.sql" ''
        SELECT * FROM employee WHERE id = 1;
      '';

      dataTest = pkgs.writeScript "postgresql-tests" ''
        set -e
        createdb employees
        psql --echo-all -d employees < ${insertSql}
        psql --echo-all -d employees < ${selectSql} | grep -5 "John Doe"
      '';

      psql = "sudo -u postgres -- psql";

      createTemporalExtension =
        if lib.versionAtLeast version "12"
        then "CREATE EXTENSION periods CASCADE"
        else "CREATE EXTENSION temporal_tables";

      sensuCheck = testlib.sensuCheckCmd nodes.machine;
    in
    ''
      machine.wait_for_unit("postgresql.service")
      machine.wait_for_open_port(5432)

      with subtest("simple data round trip should work"):
        machine.succeed('sudo -u postgres -- sh ${dataTest}')

      with subtest("postgres user should be able to connect via local socket"):
        machine.succeed('${psql} -c "SELECT \'hello\'" | grep hello')

      with subtest("creating a test user with a password should work"):
        machine.succeed('${psql} -c "CREATE USER test; ALTER USER test WITH PASSWORD \'test\'"')

      with subtest("test user should be able to connect via IPv4"):
        machine.succeed('${psql} postgresql://test:test@${ipv4}:5432/postgres -c "SELECT \'hello IPv4\'" | grep IPv4')

      with subtest("test user should be able to connect via IPv6"):
        machine.succeed('${psql} postgresql://test:test@[${ipv6}]:5432/postgres -c "SELECT \'hello IPv6\'" | grep IPv6')

      with subtest("should not trust connections via TCP"):
        machine.fail('psql --no-password -h localhost -l')

      with subtest("unprivileged user should not be able to access postgres DB via predefined roles"):
        machine.fail("sudo -u nobody psql -U postgres -l")
        machine.fail("sudo -u nobody psql -U root -l")
        machine.fail("sudo -u nobody psql -U fcio_monitoring -l")
        machine.fail("sudo -u nobody sudo -nu postgres psql -l")

      with subtest("user telegraf should be able to connect to monitoring DB via socket"):
        machine.succeed("sudo -u telegraf psql -U fcio_monitoring fcio_monitoring -l")

      with subtest("user sensuclient should be able to connect to monitoring DB via socket"):
        machine.succeed("sudo -u sensuclient psql -U fcio_monitoring fcio_monitoring -l")

      with subtest("service user should be able to write to local config dir"):
        machine.succeed('sudo -u postgres touch /etc/local/postgresql/${version}/test')

      with subtest("creating supported extensions should work"):
        machine.succeed('${psql} employees -c "CREATE EXTENSION pg_stat_statements;"')
        machine.succeed('${psql} employees -c "CREATE EXTENSION rum;"')
        machine.succeed('${psql} employees -c "${createTemporalExtension};"')
        machine.succeed('${psql} employees -c "CREATE EXTENSION postgis;"')

      with subtest("sensu check should be green"):
        machine.succeed("sudo -u sensuclient ${sensuCheck "postgresql-alive"}")

      with subtest("killing the postgres process should trigger an automatic restart"):
        machine.succeed("systemctl kill -s KILL postgresql")
        machine.sleep(1)
        machine.wait_until_succeeds("sudo -u sensuclient ${sensuCheck "postgresql-alive"}")

      with subtest("status check should be red after shutting down postgresql"):
        machine.systemctl('stop postgresql')
        machine.wait_until_fails("sudo -u sensuclient ${sensuCheck "postgresql-alive"}")
    '';

})
