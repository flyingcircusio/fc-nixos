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
      "1000" = [ ];
      "1001" = [ "admins" ];
      "1002" = [ "sudo-srv" ];
      "1003" = [ "wheel" ];
    }) ++ [
      {
        class = "service";
        gid = 101;
        home_directory = "/home/s-service";
        id = 1074;
        login_shell = "/bin/bash";
        name = "s-service";
        # password = hum1pass
        password = "$6$tCkMUKawIO9w90qR$e0v.8fedV8mm.kLs7M9zN6z0tYG9YLpuJxCM.KiB4P4Nf7lU1l9P7HSbTuziLzjRR/qBrcf.BJRjajrAid1sl.";
        permissions.test = [];
        ssh_pubkey = [];
        uid = "s-service";
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
      $out = $machine->succeed("id s-service");
      $out eq "uid=1074(s-service) gid=900(service) groups=900(service)\n"
        or die $out;
    };

    sub login {
      my ($user, $tty) = @_;
      $machine->sendKeys("alt-f$tty");
      $machine->sleep(1);
      $machine->waitUntilTTYMatches($tty, "login:");
      $machine->sendChars($user . "\n");
      $machine->waitUntilTTYMatches($tty, "Password:");
      $machine->sendChars("hum1pass\n");
      $machine->waitUntilTTYMatches($tty, "\$");
    };

    # Each user gets its own tty. 
    # Avoids strange logout problems and keeps the output for interactive inspection.
    # Inspect tty contents in the interactive test driver with: 
    # print($machine->getTTYText(1));

    login("u1000", 1);

    subtest "unprivileged user should not be able to sudo", sub {
      $machine->sendChars("sudo -l -u root id || echo failed1\n");
      $machine->waitUntilTTYMatches(1, "failed1");
      $machine->sendChars("sudo -l -u s-service id || echo failed2\n");
      $machine->waitUntilTTYMatches(1, "failed2");
    };

    subtest "unprivileged user should be able to run ipXtables without password", sub {
      $machine->sendChars("sudo -n iptables && echo 'pw not required iptables'\n");
      $machine->waitUntilTTYMatches(1, "pw not required iptables");

      $machine->sendChars("sudo -n ip6tables && echo 'pw not required ip6tables'\n");
      $machine->waitUntilTTYMatches(1, "pw not required ip6tables");
    };

    login("u1001", 2);

    subtest "admins should be able to sudo", sub {
      $machine->sendChars("sudo -l -u root id || echo failed3\n");
      $machine->waitUntilTTYMatches(2, "/run/current-system/sw/bin/id");
      $machine->sendChars("sudo -l -u s-service id || echo failed4\n");
      $machine->waitUntilTTYMatches(2, "/run/current-system/sw/bin/id");
    };

    subtest "admins sudo should require a password", sub {
      $machine->sendChars("sudo -n true || echo 'pw required admins'\n");
      $machine->waitUntilTTYMatches(2, "pw required admins");
    };

    login("u1002", 3);

    subtest "sudo-srv should grant restricted sudo", sub {
      $machine->sendChars("sudo -l -u root id || echo failed5\n");
      $machine->waitUntilTTYMatches(3, "failed5");
      $machine->sendChars("sudo -l -u s-service id || echo failed6\n");
      $machine->waitUntilTTYMatches(3, "/run/current-system/sw/bin/id");
    };

    subtest "sudo-srv should be able to become service user without password", sub {
      $machine->sendChars("sudo -niu s-service\n");
      $machine->waitUntilTTYMatches(3, 's-service@machine');
    };
    
    subtest "sudo-srv should be able to run systemctl without password", sub {
      $machine->sendChars("sudo -n systemctl --no-pager && echo 'pw not required systemctl'\n");
      $machine->waitUntilTTYMatches(3, "pw not required systemctl");
    };

    subtest "sudo-srv should be able to run fc-manage without password", sub {
      $machine->sendChars("sudo -n fc-manage && echo 'pw not required fc-manage'\n");
      $machine->waitUntilTTYMatches(3, "pw not required fc-manage");
    };

    subtest "sudo-srv user should be able to run iotop without password", sub {
      $machine->sendChars("sudo -n iotop -n1 && echo 'pw not required iotop'\n");
      $machine->waitUntilTTYMatches(3, "pw not required iotop");
    };

    login("u1003", 4);

    subtest "wheel sudo should require a password", sub {
      $machine->sendChars("sudo -n true || echo 'pw required wheel'\n");
      $machine->waitUntilTTYMatches(4, "pw required wheel");
    };

    login("s-service", 5);

    subtest "service user should be able to run systemctl without password", sub {
      $machine->sendChars("sudo -n systemctl --no-pager && echo 'pw not required systemctl'\n");
      $machine->waitUntilTTYMatches(5, "pw not required systemctl");
    };

    subtest "service user should be able to run fc-manage without password", sub {
      $machine->sendChars("sudo -n fc-manage  && echo 'pw not required fc-manage'\n");
      $machine->waitUntilTTYMatches(5, "pw not required fc-manage");
    };

    subtest "service user should be able to run iotop without password", sub {
      $machine->sendChars("sudo -n iotop -n1 && echo 'pw not required iotop'\n");
      $machine->waitUntilTTYMatches(5, "pw not required iotop");
    };

    subtest "service user should be able to run ipXtables without password", sub {
      $machine->sendChars("sudo -n iptables && echo 'pw not required iptables'\n");
      $machine->waitUntilTTYMatches(5, "pw not required iptables");

      $machine->sendChars("sudo -n ip6tables && echo 'pw not required ip6tables'\n");
      $machine->waitUntilTTYMatches(5, "pw not required ip6tables");
    };

  '';
})
