import ./make-test.nix ({ lib, ... }:

{
  name = "journal";
  machine =
    { pkgs, lib, config, ... }:
    {
      imports = [
        ../nixos
      ];

      users.groups = {
        admins = {};
        sudo-srv = {};
        service = {};
      };

      users.users =
        lib.mapAttrs'
          (id: groups:
            lib.nameValuePair
              "u${id}"
              {
                uid = builtins.fromJSON id;
                extraGroups = groups;
                isNormalUser = true;
              }
          )
          {
            "1000" = [ ];
            "1001" = [ "admins" ];
            "1002" = [ "sudo-srv" ];
            "1003" = [ "wheel" ];
            "1004" = [ "service" ];
            "1005" = [ "systemd-journal" ];
          };
    };

  testScript = ''
    $machine->waitForUnit('multi-user.target');

    subtest "user without allowed groups should not see the journal", sub {
      $machine->mustFail('sudo -iu \#1000 journalctl');
    };

    subtest "admin user should see the journal", sub {
      $machine->succeed('sudo -iu \#1001 journalctl');
    };

    subtest "admin user should see the journal", sub {
      $machine->succeed('sudo -iu \#1002 journalctl');
    };

    subtest "wheel user should see the journal", sub {
      $machine->succeed('sudo -iu \#1003 journalctl');
    };

    subtest "service user should see the journal", sub {
      $machine->succeed('sudo -iu \#1004 journalctl');
    };

    print($machine->succeed('getfacl /var/log/journal'));
  '';
})
