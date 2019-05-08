import ./make-test.nix ({ rolename ? "postgresql10", lib, pkgs, ... }:
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

      createExtensions = pkgs.writeScript "extension-tests" ''
        set -e
        psql employees -c "CREATE EXTENSION postgis;"
        psql employees -c "CREATE EXTENSION temporal_tables;"
      '';
    in
    ''
      $machine->waitForUnit("postgresql.service");
      $machine->waitForOpenPort(5432);

      # simple data round trip
      $machine->succeed('sudo -u postgres -- sh ${dataTest}');

      # connection tests with password
      $machine->succeed('sudo -u postgres -- psql -c "CREATE USER test; ALTER USER test WITH PASSWORD \'test\'"');
      $machine->succeed('sudo -u postgres -- psql postgresql://test:test@${ipv4}:5432/postgres -c "SELECT \'hello\'" | grep hello');
      $machine->succeed('sudo -u postgres -- psql postgresql://test:test@[${ipv6}]:5432/postgres -c "SELECT \'hello\'" | grep hello');

      # should not trust connections via TCP
      $machine->fail('psql --no-password -h localhost -l');

      # test extensions that work on all versions
      $machine->succeed('sudo -u postgres -- sh ${createExtensions}');
    '' +
      lib.optionalString  (rolename != "postgresql95")
    ''# Do the rum extension test. Rum is not available for 9.5.
      $machine->succeed('sudo -u postgres -- psql employees -c "CREATE EXTENSION rum;"');
    '';
})
