import ./make-test-python.nix ({ lib, ... }:

{
  name = "journal";
  machine =
    { pkgs, lib, config, ... }:
    {
      imports = [ ../nixos ../nixos/roles ];

      users.groups = {
        admins = {};
        sudo-srv = {};
        service = {};
      };

      flyingcircus.enc.parameters.interfaces.srv = {
        mac = "52:54:00:12:34:56";
        bridged = false;
        networks = {
          "192.168.101.0/24" = [ "192.168.101.1" ];
          "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::1" ];
        };
        gateways = {};
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
    machine.wait_for_unit('multi-user.target')

    with subtest("user without allowed groups should not see the journal"):
        machine.fail('sudo -iu \#1000 journalctl')

    with subtest("admin user should see the journal"):
        machine.succeed('sudo -iu \#1001 journalctl')

    with subtest("admin user should see the journal"):
        machine.succeed('sudo -iu \#1002 journalctl')

    with subtest("wheel user should see the journal"):
        machine.succeed('sudo -iu \#1003 journalctl')

    with subtest("service user should see the journal"):
        machine.succeed('sudo -iu \#1004 journalctl')

    print(machine.succeed('getfacl /var/log/journal'))
  '';
})
