import ../make-test-python.nix (
  {
    lib,
    testlib,
    pkgs,
    ...
  }:
  let
    release = import ../../release { };
    channel = release.release.src;

    insertSql = pkgs.writeText "insert.sql" ''
      CREATE TABLE employee (
        id INT PRIMARY KEY,
        name TEXT
      );
      INSERT INTO employee VALUES (1, 'John Doe');
    '';

    dataTest = pkgs.writeScript "postgresql-tests" ''
      set -e
      createdb employees
      psql --echo-all -d employees < ${insertSql}
    '';

    psql = "sudo -u postgres -- psql";
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

      machine.wait_for_unit("postgresql.service")
      machine.wait_for_open_port(5432)

      machine.succeed('sudo -u postgres -- sh ${dataTest}')
    '';

  in
  {
    name = "postgresql-upgrade";
    testCases = {
      manual = {
        name = "manual";
        nodes = {
          machine =
            { ... }:
            {
              imports = [
                (testlib.fcConfig { net.fe = false; })
              ];

              flyingcircus.roles.postgresql13.enable = lib.mkDefault true;

              specialisation = {
                pg14.configuration = {
                  flyingcircus.roles.postgresql13.enable = false;
                  flyingcircus.roles.postgresql14.enable = true;
                };
                pg15.configuration = {
                  flyingcircus.roles.postgresql13.enable = false;
                  flyingcircus.roles.postgresql15.enable = true;
                };
                pg16.configuration = {
                  flyingcircus.roles.postgresql13.enable = false;
                  flyingcircus.roles.postgresql16.enable = true;
                };
              };

              system.extraDependencies = with pkgs; [
                # these attributes are being `nix-build` by `fc-postgresql` at
                # upgrade time. Ensure these are already present in the nix store
                # to avoid building them in the sandboxed test.
                (postgresql_13.withPackages (ps: [ ]))
                (postgresql_14.withPackages (ps: [ ]))
                (postgresql_15.withPackages (ps: [ ]))
                (postgresql_16.withPackages (ps: [ ]))
              ];
            };
        };

        testScript = ''
          ${testSetup}
          with subtest("prepare-autoupgrade should fail when the option is not enabled"):
            machine.fail("${fc-postgresql} prepare-autoupgrade --new-version 14")

          with subtest("prepare should fail with unexpected database employees"):
            machine.fail('${fc-postgresql} upgrade --new-version 14')

          print(machine.succeed("${fc-postgresql} list-versions"))

          with subtest("prepare upgrade 13 -> 14"):
            machine.succeed('${fc-postgresql} upgrade --new-version 14 --expected employees')
            machine.succeed("stat /srv/postgresql/14/fcio_upgrade_prepared")
            # postgresql should still run
            machine.succeed("systemctl status postgresql")
            print(machine.succeed("${fc-postgresql} list-versions"))

          with subtest("upgrade 13 -> 14 from prepared state"):
            machine.succeed('${fc-postgresql} upgrade --expected employees --new-version 14 --stop --upgrade-now')
            machine.succeed("stat /srv/postgresql/13/fcio_migrated_to")
            machine.succeed("stat /srv/postgresql/14/fcio_migrated_from")
            # postgresql should be stopped
            machine.fail("systemctl status postgresql")
            print(machine.succeed("${fc-postgresql} list-versions"))

          # Clean up migration and start postgresql13 again for the next round.
          machine.execute("rm -rf /srv/postgresql/14")
          machine.execute("rm -rf /srv/postgresql/13/fcio_migrated_to")
          machine.systemctl("start postgresql")

          with subtest("upgrade 13 -> 15 in one step"):
            machine.succeed('${fc-postgresql} upgrade --expected employees --new-version 15 --stop --upgrade-now')
            machine.succeed("stat /srv/postgresql/13/fcio_migrated_to")
            machine.succeed("stat /srv/postgresql/15/fcio_migrated_from")
            # postgresql should be stopped
            machine.fail("systemctl status postgresql")
            # move to pg15 role and wait for postgresql to start
            switch_to(machine, "pg15")
            machine.wait_for_unit("postgresql")
            print(machine.succeed("${fc-postgresql} list-versions"))

          with subtest("upgrade 15 -> 16 in one step"):
            machine.succeed('${fc-postgresql} upgrade --expected employees --new-version 16 --stop --upgrade-now')
            machine.succeed("stat /srv/postgresql/15/fcio_migrated_to")
            machine.succeed("stat /srv/postgresql/16/fcio_migrated_from")
            switch_to(machine, "pg16")
            machine.wait_for_unit("postgresql")
            print(machine.succeed("${fc-postgresql} list-versions"))
        '';
      };
      automatic = {
        name = "automatic";
        nodes = {
          machine =
            { ... }:
            {
              imports = [
                (testlib.fcConfig { net.fe = false; })
              ];

              flyingcircus.roles.postgresql13.enable = lib.mkDefault true;
              flyingcircus.services.postgresql.autoUpgrade = {
                enable = true;
                expectedDatabases = [ "employees" ];
              };

              specialisation = {
                pg14UnexpectedDb.configuration = {
                  flyingcircus.roles.postgresql13.enable = false;
                  flyingcircus.roles.postgresql14.enable = true;
                  flyingcircus.services.postgresql.autoUpgrade.expectedDatabases = lib.mkForce [ ];
                };
                pg14.configuration = {
                  flyingcircus.roles.postgresql13.enable = false;
                  flyingcircus.roles.postgresql14.enable = true;
                };
                pg15.configuration = {
                  flyingcircus.roles.postgresql13.enable = false;
                  flyingcircus.roles.postgresql15.enable = true;
                };
                pg16.configuration = {
                  flyingcircus.roles.postgresql13.enable = false;
                  flyingcircus.roles.postgresql16.enable = true;
                };
              };

              system.extraDependencies = with pkgs; [
                # these attributes are being `nix-build` by `fc-postgresql` at
                # upgrade time. Ensure these are already present in the nix store
                # to avoid building them in the sandboxed test.
                (postgresql_13.withPackages (ps: [ ]))
                (postgresql_14.withPackages (ps: [ ]))
                (postgresql_15.withPackages (ps: [ ]))
                (postgresql_16.withPackages (ps: [ ]))
              ];
            };
        };

        testScript = ''
          ${testSetup}
          print(machine.succeed("${fc-postgresql} list-versions"))

          with subtest("autoupgrade should refuse when unexpected DB is present"):
            switch_to(machine, "pg14UnexpectedDb", expect="fail")
            machine.fail("systemctl status postgresql")
            print(machine.succeed("${fc-postgresql} list-versions"))

          with subtest("prepare autoupgrade should fail when unexpected DB is present"):
            machine.fail('${fc-postgresql} prepare-autoupgrade --new-version 14')
            print(machine.succeed("${fc-postgresql} list-versions"))

          with subtest("autoupgrade 13 -> 14"):
            # move to new role and wait for postgresql to start
            switch_to(machine, "pg14")
            machine.wait_for_unit("postgresql")
            machine.succeed("stat /srv/postgresql/13/fcio_migrated_to")
            machine.succeed("stat /srv/postgresql/14/fcio_migrated_from")
            print(machine.succeed("${fc-postgresql} list-versions"))

          with subtest("prepare autoupgrade 14 -> 15"):
            machine.succeed('${fc-postgresql} prepare-autoupgrade --new-version 15')
            machine.succeed("stat /srv/postgresql/15/fcio_upgrade_prepared")
            # postgresql should still run
            machine.succeed("systemctl status postgresql")
            print(machine.succeed("${fc-postgresql} list-versions"))


          with subtest("autoupgrade 14 -> 15"):
            # move to new role and wait for postgresql to start
            switch_to(machine, "pg15")
            machine.wait_for_unit("postgresql")
            machine.succeed("stat /srv/postgresql/14/fcio_migrated_to")
            machine.succeed("stat /srv/postgresql/15/fcio_migrated_from")
            print(machine.succeed("${fc-postgresql} list-versions"))

          with subtest("autoupgrade 15 -> 16"):
            # move to new role and wait for postgresql to start
            switch_to(machine, "pg16")
            machine.wait_for_unit("postgresql")
            machine.succeed("stat /srv/postgresql/15/fcio_migrated_to")
            machine.succeed("stat /srv/postgresql/16/fcio_migrated_from")
            print(machine.succeed("${fc-postgresql} list-versions"))
        '';
      };
    };
  }
)
