import ./make-test-python.nix ({ pkgs, testlib, ... }:
{
  name = "fc-agent";
  testCases = {
    prod = {
      name = "prod";
      machine =
        { config, lib, ... }:
        {
          imports = [
            (testlib.fcConfig { extraEncParameters = { production = true; }; })
          ];
        };
      testScript = ''
        machine.wait_for_unit('multi-user.target')
        machine.succeed("systemctl show fc-update-channel.service --property ExecStart | grep 'request update'")
      '';
    };
    nonprod = {
      name = "nonprod";
      machine =
        { config, lib, ... }:
        {
          imports = [
            (testlib.fcConfig { extraEncParameters = { production = false; }; })
          ];
        };
      testScript = ''
        machine.wait_for_unit('multi-user.target')
        machine.succeed("systemctl show fc-update-channel.service --property ExecStart | grep 'switch --update-channel'")
      '';
    };
  };
})
