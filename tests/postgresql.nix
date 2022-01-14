import ./make-test-python.nix ({ rolename ? "postgresql13", lib, pkgs, ... }:
let
  ipv4 = "192.168.101.1";
  ipv6 = "2001:db8:f030:1c3::1";
in {
  name = "postgresql";
  machine =
    { ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
      flyingcircus.roles.${rolename}.enable = true;

      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:34:56";
          bridged = false;
          networks = {
            "192.168.101.0/24" = [ ipv4 ];
            "2001:db8:f030:1c3::/64" = [ ipv6 ];
          };
          gateways = {};
        };
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
        if (rolename == "postgresql12" || rolename == "postgresql13")
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
    '' + lib.optionalString (rolename != "postgresql12") ''
      # Postgis fails only on postgresql12 with an OOM that produces no other output
      # for debugging. It's caused by the shared library for pg_stat_statements.
      # It works on real VMs so just skip it here. Creating it in the test
      # works on NixOS 21.11, though, we can re-enable it there.
      machine.succeed('${psql} employees -c "CREATE EXTENSION postgis;"')
    '';


})
