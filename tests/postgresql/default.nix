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
    in
    ''
      machine.wait_for_unit("postgresql.service")
      machine.wait_for_open_port(5432)

      # simple data round trip
      machine.succeed('sudo -u postgres -- sh ${dataTest}')

      # connection tests with password
      machine.succeed('${psql} -c "CREATE USER test; ALTER USER test WITH PASSWORD \'test\'"')
      machine.succeed('${psql} postgresql://test:test@${ipv4}:5432/postgres -c "SELECT \'hello\'" | grep hello')
      machine.succeed('${psql} postgresql://test:test@[${ipv6}]:5432/postgres -c "SELECT \'hello\'" | grep hello')

      # should not trust connections via TCP
      machine.fail('psql --no-password -h localhost -l')

      # service user should be able to write to local config dir
      machine.succeed('sudo -u postgres touch `echo /etc/local/postgresql/*`/test')

      machine.succeed('${psql} employees -c "CREATE EXTENSION pg_stat_statements;"')
      machine.succeed('${psql} employees -c "CREATE EXTENSION rum;"')
      machine.succeed('${psql} employees -c "${createTemporalExtension};"')
      machine.succeed('${psql} employees -c "CREATE EXTENSION postgis;"')
    '';


})
