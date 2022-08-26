import ./make-test-python.nix ({ lib, testlib, ... }:

{
  name = "journal";
  nodes = {
    machine =
      { pkgs, lib, config, ... }:
      {
        imports = [
            (testlib.fcConfig {})
          ];

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

    with subtest("Activation scripts should run without errors"):
      output = machine.succeed("bash -e /run/current-system/activate 2>&1")
      assert "skipping ACL" not in output

    print(output)

    print(machine.succeed('getfacl /var/log/journal'))
  '';
})
