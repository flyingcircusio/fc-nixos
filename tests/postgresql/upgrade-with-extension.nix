import ../make-test-python.nix ({lib, testlib, pkgs, ... }:
let
  release = import ../../release {};
  channel = release.release.src;

  insertSql = pkgs.writeText "insert.sql" ''
    create extension anon cascade;
    select anon.init();
    create table player(id serial, name text, points int);
    insert into player(id,name,points) values (1,'Foo', 23);
    insert into player(id,name,points) values (2,'Bar',42);
    security label for anon on column player.name is 'MASKED WITH FUNCTION anon.fake_last_name();';
    security label for anon on column player.points is 'MASKED WITH VALUE NULL';
  '';

  dataTest = pkgs.writeScript "postgresql-tests" ''
    set -e
    createdb anonymized
    psql -v ON_ERROR_STOP=1 --echo-all -d anonymized < ${insertSql}
  '';

  fc-postgresql = "sudo -u postgres -- fc-postgresql";

  testSetup = ''
    # Make nix-build work inside the VM
    machine.execute("mkdir -p /nix/var/nix/profiles/per-user/root/")
    machine.execute("ln -s ${channel} /nix/var/nix/profiles/per-user/root/channels")

    # Taken from upstream acme.nix
    def switch_to(node, name, expect="succeed"):
        # On first switch, this will create a symlink to the current system so that we can
        # quickly switch between derivations
        root_specs = "/tmp/specialisation"
        node.execute(
          f"test -e {root_specs}"
          f" || ln -s $(readlink /run/current-system)/specialisation {root_specs}"
        )

        switcher_path = f"/run/current-system/specialisation/{name}/bin/switch-to-configuration"
        rc, _ = node.execute(f"test -e '{switcher_path}'")
        if rc > 0:
            switcher_path = f"/tmp/specialisation/{name}/bin/switch-to-configuration"

        if expect == "fail":
          node.fail(f"{switcher_path} test")
        else:
          node.succeed(f"{switcher_path} test")

    # helpers from the pg_anonymizer test in nixpkgs
    def get_player_table_contents():
        return [
            x.split(',') for x in machine.succeed("sudo -u postgres psql -d anonymized --csv --command 'select * from player'").splitlines()[1:]
        ]

    def check_anonymized_row(row, id, original_name):
        assert row[0] == id, f"Expected first row to have ID {id}, but got {row[0]}"
        assert row[1] != original_name, f"Expected first row to have a name other than {original_name}"
        assert not bool(row[2]), "Expected points to be NULL in first row"

    def check_original_data(output):
        assert output[0] == ['1','Foo','23'], f"Expected first row from player table to be 1,Foo,23; got {output[0]}"
        assert output[1] == ['2','Bar','42'], f"Expected first row from player table to be 2,Bar,42; got {output[1]}"

    def check_anonymized_rows(output):
        check_anonymized_row(output[0], '1', 'Foo')
        check_anonymized_row(output[1], '2', 'Bar')

    machine.wait_for_unit("postgresql.service")
    machine.wait_for_open_port(5432)

    machine.succeed('sudo -u postgres -- sh ${dataTest}')

    with subtest("Anonymize DB"):
        check_original_data(get_player_table_contents())
        machine.succeed("sudo -u postgres psql -d anonymized --command 'select anon.anonymize_database();'")
  '';

in {
  name = "postgresql-upgrade-with-extensions";
  testCases = {
    manual = {
      name = "manual";
      nodes = {
        machine = { ... }: {
          imports = [
            (testlib.fcConfig { net.fe = false; })
          ];

          flyingcircus.roles.postgresql12.enable = lib.mkDefault true;
          services.postgresql = {
            extraPlugins = ps: with ps; [ anonymizer ];
            settings.shared_preload_libraries = lib.mkForce "auto_explain, pg_stat_statements, anon";
          };

          specialisation = {
            pg13.configuration = {
              flyingcircus.roles.postgresql12.enable = false;
              flyingcircus.roles.postgresql13.enable = true;
            };
            pg14.configuration = {
              flyingcircus.roles.postgresql12.enable = false;
              flyingcircus.roles.postgresql14.enable = true;
            };
            pg15.configuration = {
              flyingcircus.roles.postgresql12.enable = false;
              flyingcircus.roles.postgresql15.enable = true;
            };
          };

          system.extraDependencies = with pkgs; [
            (postgresql_12.withPackages (ps: with ps; [ anonymizer ]))
            (postgresql_13.withPackages (ps: with ps; [ anonymizer ]))
            (postgresql_14.withPackages (ps: with ps; [ anonymizer ]))
            (postgresql_15.withPackages (ps: with ps; [ anonymizer ]))
            (postgresql_12.withPackages (ps: [ ]))
            (postgresql_13.withPackages (ps: [ ]))
            (postgresql_14.withPackages (ps: [ ]))
            (postgresql_15.withPackages (ps: [ ]))
          ];
        };
      };

      testScript = ''
        ${testSetup}

        with subtest("prepare-autoupgrade should fail when the option is not enabled"):
          machine.fail("${fc-postgresql} prepare-autoupgrade --new-version 13")

        with subtest("prepare should fail with unexpected database anonymized"):
          machine.fail('${fc-postgresql} upgrade --new-version 13')

        print(machine.succeed("${fc-postgresql} list-versions"))

        with subtest("prepare upgrade 12 -> 13"):
          machine.fail('${fc-postgresql} upgrade --new-version 13 --expected anonymized')
          machine.succeed("rm -f /srv/postgresql/12/fcio_stopper && systemctl start postgresql")
          machine.succeed('${fc-postgresql} upgrade --new-version 13 --expected anonymized --extension-names anonymizer')
          machine.succeed("stat /srv/postgresql/13/fcio_upgrade_prepared")
          # postgresql should still run
          machine.succeed("systemctl status postgresql")
          print(machine.succeed("${fc-postgresql} list-versions"))

        with subtest("upgrade 12 -> 13 from prepared state"):
          machine.succeed("systemctl status postgresql")
          machine.succeed("rm -f /srv/postgresql/13/pg_upgrade_server.log")
          print(machine.succeed('${fc-postgresql} upgrade --expected anonymized --new-version 13 --stop --upgrade-now --extension-names anonymizer || cat /srv/postgresql/13/pg_upgrade_server.log'))
          machine.succeed("stat /srv/postgresql/12/fcio_migrated_to")
          machine.succeed("stat /srv/postgresql/13/fcio_migrated_from")
          # postgresql should be stopped
          machine.fail("systemctl status postgresql")
          print(machine.succeed("${fc-postgresql} list-versions"))

        # Clean up migration and start postgresql12 again for the next round.
        machine.execute("rm -rf /srv/postgresql/13")
        machine.execute("rm -rf /srv/postgresql/12/fcio_migrated_to")
        machine.systemctl("start postgresql")

        with subtest("upgrade 12 -> 14 in one step"):
          machine.succeed('${fc-postgresql} upgrade --expected anonymized --new-version 14 --stop --upgrade-now --extension-names anonymizer')
          machine.succeed("stat /srv/postgresql/12/fcio_migrated_to")
          machine.succeed("stat /srv/postgresql/14/fcio_migrated_from")
          # postgresql should be stopped
          machine.fail("systemctl status postgresql")
          # move to pg14 role and wait for postgresql to start
          switch_to(machine, "pg14")
          machine.wait_for_unit("postgresql")
          print(machine.succeed("${fc-postgresql} list-versions"))
          check_anonymized_rows(get_player_table_contents())

        with subtest("upgrade 14 -> 15 in one step"):
          machine.succeed('${fc-postgresql} upgrade --expected anonymized --new-version 15 --stop --upgrade-now --extension-names anonymizer')
          machine.succeed("stat /srv/postgresql/14/fcio_migrated_to")
          machine.succeed("stat /srv/postgresql/15/fcio_migrated_from")
          switch_to(machine, "pg15")
          machine.wait_for_unit("postgresql")
          print(machine.succeed("${fc-postgresql} list-versions"))
          check_anonymized_rows(get_player_table_contents())
      '';
    };
    automatic = {
      name = "automatic";
      nodes = {
        machine = { ... }: {
          imports = [
            (testlib.fcConfig { net.fe = false; })
          ];

          flyingcircus.roles.postgresql12.enable = lib.mkDefault true;
          flyingcircus.services.postgresql.autoUpgrade = {
            enable = true;
            expectedDatabases = [ "anonymized" ];
          };
          services.postgresql = {
            extraPlugins = ps: with ps; [ anonymizer ];
            settings.shared_preload_libraries = lib.mkForce "auto_explain, pg_stat_statements, anon";
          };

          specialisation = {
            pg13UnexpectedDb.configuration = {
              flyingcircus.roles.postgresql12.enable = false;
              flyingcircus.roles.postgresql13.enable = true;
              flyingcircus.services.postgresql.autoUpgrade.expectedDatabases = lib.mkForce [];
            };
            pg13.configuration = {
              flyingcircus.roles.postgresql12.enable = false;
              flyingcircus.roles.postgresql13.enable = true;
            };
            pg14.configuration = {
              flyingcircus.roles.postgresql12.enable = false;
              flyingcircus.roles.postgresql14.enable = true;
            };
            pg15.configuration = {
              flyingcircus.roles.postgresql12.enable = false;
              flyingcircus.roles.postgresql15.enable = true;
            };
          };

          system.extraDependencies = with pkgs; [
            (postgresql_12.withPackages (ps: with ps; [ anonymizer ]))
            (postgresql_13.withPackages (ps: with ps; [ anonymizer ]))
            (postgresql_14.withPackages (ps: with ps; [ anonymizer ]))
            (postgresql_15.withPackages (ps: with ps; [ anonymizer ]))
            (postgresql_12.withPackages (ps: [ ]))
            (postgresql_13.withPackages (ps: [ ]))
            (postgresql_14.withPackages (ps: [ ]))
            (postgresql_15.withPackages (ps: [ ]))
          ];
        };
      };

      testScript = ''
        ${testSetup}
        print(machine.succeed("${fc-postgresql} list-versions"))

        with subtest("autoupgrade should refuse when unexpected DB is present"):
          switch_to(machine, "pg13UnexpectedDb", expect="fail")
          machine.fail("systemctl status postgresql")
          print(machine.succeed("${fc-postgresql} list-versions"))

        with subtest("prepare autoupgrade should fail when unexpected DB is present"):
          machine.fail('${fc-postgresql} prepare-autoupgrade --new-version 13')
          print(machine.succeed("${fc-postgresql} list-versions"))

        with subtest("autoupgrade 12 -> 13"):
          # move to new role and wait for postgresql to start
          switch_to(machine, "pg13")
          machine.wait_for_unit("postgresql")
          machine.succeed("stat /srv/postgresql/12/fcio_migrated_to")
          machine.succeed("stat /srv/postgresql/13/fcio_migrated_from")
          print(machine.succeed("${fc-postgresql} list-versions"))

        with subtest("prepare autoupgrade 13 -> 14"):
          machine.succeed('${fc-postgresql} prepare-autoupgrade --new-version 14 --extension-names anonymizer')
          machine.succeed("stat /srv/postgresql/14/fcio_upgrade_prepared")
          # postgresql should still run
          machine.succeed("systemctl status postgresql")
          print(machine.succeed("${fc-postgresql} list-versions"))


        with subtest("autoupgrade 13 -> 14"):
          # move to new role and wait for postgresql to start
          switch_to(machine, "pg14")
          machine.wait_for_unit("postgresql")
          machine.succeed("stat /srv/postgresql/13/fcio_migrated_to")
          machine.succeed("stat /srv/postgresql/14/fcio_migrated_from")
          print(machine.succeed("${fc-postgresql} list-versions"))
          check_anonymized_rows(get_player_table_contents())

        with subtest("autoupgrade 14 -> 15"):
          # move to new role and wait for postgresql to start
          switch_to(machine, "pg15")
          machine.wait_for_unit("postgresql")
          machine.succeed("stat /srv/postgresql/14/fcio_migrated_to")
          machine.succeed("stat /srv/postgresql/15/fcio_migrated_from")
          print(machine.succeed("${fc-postgresql} list-versions"))
          check_anonymized_rows(get_player_table_contents())
      '';
    };
  };
})
