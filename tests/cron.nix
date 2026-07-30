import ./make-test-python.nix (
  { testlib, ... }:
  {
    name = "cron";

    nodes.machine = {
      imports = [ (testlib.fcConfig { }) ];
    };

    testScript = ''
      machine.succeed("test \"$(systemctl show --property=Restart --value cron.service)\" = always")
    '';
  }
)
