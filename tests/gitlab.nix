# Taken from nixpkgs and customized for our gitlab role.

let
  initialRootPassword = "notproduction";
  dbPassword = "xo0daiF4";
  ipv4 = "192.168.1.1";
  ipv6 = "2001:db8:f030:1c3::1";
in
import ./make-test-python.nix ({ pkgs, lib, testlib, ...} : with lib; {
  name = "gitlab";

  nodes = {
    gitlab = { lib, ... }: {
      imports = [
        (testlib.fcConfig { })
      ];

      virtualisation.memorySize = 4096;
      virtualisation.qemu.options = [ "-smp 2" ];

      flyingcircus.roles.gitlab = {
        enable = true;
        hostName = "gitlab";
      };

      flyingcircus.roles.webgateway.enable = true;

      services.nginx.virtualHosts.gitlab = {
        forceSSL = lib.mkForce false;
        enableACME = lib.mkForce false;
      };

      flyingcircus.roles.postgresql12.enable = true;

      services.redis.requirePass = "test";

      services.gitlab = lib.mkForce {
        databasePasswordFile = pkgs.writeText "dbPassword" dbPassword;
        initialRootPasswordFile = pkgs.writeText "rootPassword" initialRootPassword;
        smtp.enable = true;
        secrets = {
          secretFile = pkgs.writeText "secret" "r8X9keSKynU7p4aKlh4GO1Bo77g5a7vj";
          otpFile = pkgs.writeText "otpsecret" "Zu5hGx3YvQx40DvI8WoZJQpX2paSDOlG";
          dbFile = pkgs.writeText "dbsecret" "lsGltKWTejOf6JxCVa7nLDenzkO9wPLR";
          jwsFile = pkgs.runCommand "oidcKeyBase" {} "${pkgs.openssl}/bin/openssl genrsa 2048 > $out";
        };
      };

      systemd.services.gitlab.serviceConfig.Restart = mkForce "no";
      systemd.services.gitlab-workhorse.serviceConfig.Restart = mkForce "no";
      systemd.services.gitaly.serviceConfig.Restart = mkForce "no";
      systemd.services.gitlab-sidekiq.serviceConfig.Restart = mkForce "no";

      systemd.services.gitlab-prepare-database = rec {
        after = [ "postgresql.service" ];
        requiredBy = [ "gitlab.service" ];
        before = requiredBy;
        path = [ pkgs.postgresql_12 ];
        script = ''
          set -ex
          psql -c "CREATE USER gitlab WITH PASSWORD '${dbPassword}'"
          psql -c "CREATE DATABASE gitlab OWNER gitlab"
          psql gitlab -c "CREATE EXTENSION pg_trgm"
          psql gitlab -c "CREATE EXTENSION btree_gist"
        '';

        serviceConfig = {
          User = "postgres";
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };

    };
  };

  testScript =
  let
    auth = pkgs.writeText "auth.json" (builtins.toJSON {
      grant_type = "password";
      username = "root";
      password = initialRootPassword;
    });

    createProject = pkgs.writeText "create-project.json" (builtins.toJSON {
      name = "test";
    });

    putFile = pkgs.writeText "put-file.json" (builtins.toJSON {
      branch = "master";
      author_email = "author@example.com";
      author_name = "Firstname Lastname";
      content = "some content";
      commit_message = "create a new file";
    });
  in
  ''
    gitlab.wait_for_unit("gitlab-prepare-database.service")
    gitlab.wait_for_unit("gitaly.service")
    gitlab.wait_for_unit("gitlab-workhorse.service")
    gitlab.wait_for_unit("gitlab.service")
    gitlab.wait_for_unit("gitlab-sidekiq.service")
    gitlab.wait_for_file("/run/gitlab/gitlab-workhorse.socket")
    gitlab.wait_for_file("/srv/gitlab/state/tmp/sockets/gitlab.socket")

    gitlab.wait_until_succeeds("curl -sSf http://gitlab/users/sign_in")
    gitlab.succeed(
        "curl -isSf http://gitlab | grep -i location | grep -q http://gitlab/users/sign_in"
    )
    gitlab.succeed(
        "${pkgs.sudo}/bin/sudo -u gitlab -H gitlab-rake gitlab:check 1>&2"
    )
    gitlab.succeed(
        "echo \"Authorization: Bearer \$(curl -X POST -H 'Content-Type: application/json' -d @${auth} http://gitlab/oauth/token | ${pkgs.jq}/bin/jq -r '.access_token')\" >/tmp/headers"
    )
    gitlab.succeed(
        "curl -X POST -H 'Content-Type: application/json' -H @/tmp/headers -d @${createProject} http://gitlab/api/v4/projects"
    )
    gitlab.succeed(
        "curl -X POST -H 'Content-Type: application/json' -H @/tmp/headers -d @${putFile} http://gitlab/api/v4/projects/1/repository/files/some-file.txt"
    )
    gitlab.succeed(
        "curl -H @/tmp/headers http://gitlab/api/v4/projects/1/repository/archive.tar.gz > /tmp/archive.tar.gz"
    )
    gitlab.succeed(
        "curl -H @/tmp/headers http://gitlab/api/v4/projects/1/repository/archive.tar.bz2 > /tmp/archive.tar.bz2"
    )
    gitlab.succeed("test -s /tmp/archive.tar.gz")
    gitlab.succeed("test -s /tmp/archive.tar.bz2")
  '';
})
