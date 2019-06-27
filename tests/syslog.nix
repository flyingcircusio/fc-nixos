import ./make-test.nix ({ ... }:

let
  machine = 
    {
      imports = [ ../nixos ];
    };

in {
  name = "syslog";

  testCases = {
    disabled = {
      inherit machine;
      testScript = ''
        $machine->mustFail("systemctl list-unit-files | grep syslog.service");
      '';
    };

    enabled = {
      machine = machine // {
        flyingcircus.syslog.separateFacilities = {
          local2 = "/var/log/test.log";
        };
      };

      testScript = ''
        $machine->waitForUnit("syslog.service");
        $machine->succeed("logger -p local2.info testlog");
        $machine->sleep(0.5);
        $machine->succeed("grep testlog /var/log/test.log");
      '';
    };
  };
})
