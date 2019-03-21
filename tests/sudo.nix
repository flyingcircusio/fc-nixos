import ./make-test.nix ({ lib, ... }:

let
  userData =
    (lib.mapAttrsToList (id: groups: {
      class = "human";
      gid = 100;
      home_directory = "/home/u${id}";
      id = builtins.fromJSON id;
      login_shell = "/bin/bash";
      name = "Human User";
      # password = hum1pass
      password = "$6$tCkMUKawIO9w90qR$e0v.8fedV8mm.kLs7M9zN6z0tYG9YLpuJxCM.KiB4P4Nf7lU1l9P7HSbTuziLzjRR/qBrcf.BJRjajrAid1sl.";
      permissions.test = groups;
      ssh_pubkey = [];
      uid = "u${id}";
    })
    {
      "1000" = [];
      "1001" = [ "admins" ];
      "1002" = [ "sudo-srv" ];
    }) ++ [
      {
        class = "service";
        gid = 101;
        home_directory = "/home/test1";
        id = 1074;
        login_shell = "/bin/bash";
        name = "test1";
        password = "*";
        permissions.test = [];
        ssh_pubkey = [];
        uid = "test1";
      }
    ];

in
{
  name = "sudo";
  machine =
    { pkgs, lib, config, ... }:
    {
      imports = [
        ../nixos
      ];

      flyingcircus.users = {
        userData = userData;
        permissions = [
          {
            id = 2028;
            name = "sudo-srv";
          }
        ];
        adminsGroup = {
          gid = 2003;
          name = "admins";
        };
      };

      flyingcircus.enc.parameters.resource_group = "test";
    };

  testScript = ''
    $machine->waitForUnit('multi-user.target');

    subtest "check uids", sub {
      my $out = $machine->succeed("id u1000");
      $out eq "uid=1000(u1000) gid=100(users) groups=100(users)\n"
        or die $out;
      $out = $machine->succeed("id u1001");
      $out eq "uid=1001(u1001) gid=100(users) groups=2003(admins),100(users)\n"
        or die $out;
      $out = $machine->succeed("id u1002");
      $out eq "uid=1002(u1002) gid=100(users) groups=503(sudo-srv),100(users)\n"
        or die $out;
      $out = $machine->succeed("id test1");
      $out eq "uid=1074(test1) gid=900(service) groups=900(service)\n"
        or die $out;
    };

    sub login {
      my ($user) = @_;
      $machine->sleep(1);
      $machine->waitUntilTTYMatches(1, "login:");
      $machine->sendChars($user . "\n");
      $machine->waitUntilTTYMatches(1, "Password:");
      $machine->sendChars("hum1pass\n");
      $machine->waitUntilTTYMatches(1, "\$");
    };

    subtest "unpriviledged user should not be able to sudo", sub {
      login("u1000");
      $machine->sendChars("sudo -l -u root id || echo failed1\n");
      $machine->waitUntilTTYMatches(1, "failed1");
      $machine->sendChars("sudo -l -u test1 id || echo failed2\n");
      $machine->waitUntilTTYMatches(1, "failed2");
      $machine->sendKeys("ctrl-d");
    };

    subtest "admin should be able to sudo", sub {
      login("u1001");
      $machine->sendChars("sudo -l -u root id || echo failed3\n");
      $machine->waitUntilTTYMatches(1, "/run/current-system/sw/bin/id");
      $machine->sendChars("sudo -l -u test1 id || echo failed4\n");
      $machine->waitUntilTTYMatches(1, "/run/current-system/sw/bin/id");
      $machine->sendKeys("ctrl-d");
    };

    subtest "sudo-srv should grant restricted sudo", sub {
      login("u1002");
      $machine->sendChars("sudo -l -u root id || echo failed5\n");
      $machine->waitUntilTTYMatches(1, "failed5");
      $machine->sendChars("sudo -l -u test1 id || echo failed6\n");
      $machine->waitUntilTTYMatches(1, "/run/current-system/sw/bin/id");
      $machine->sendKeys("ctrl-d");
    };
  '';
})
