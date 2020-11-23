import ./make-test-python.nix ({ ... }:
{
  name = "logging";
  machine =
    { ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
      flyingcircus.syslog.separateFacilities = {
        local2 = "/var/log/test.log";
      };

      flyingcircus.journalbeat.logTargets = {
        "localhost" = {
          host = "localhost";
          port = 12301;
        };
      };
    };

  testScript = ''
    machine.wait_for_unit("syslog.service")

    with subtest("logging to UDP should go to journal"):
      machine.succeed("logger -h localhost TEST_UDP")
      machine.wait_until_succeeds("journalctl | grep TEST_UDP")

    with subtest("logging to separate facility via UDP should go to logfile"):
      machine.succeed("logger -p local2.info -h localhost TEST_LOCAL2_INFO")
      machine.wait_until_succeeds("grep TEST_LOCAL2_INFO /var/log/test.log")

    machine.wait_for_unit("journalbeat-localhost.service")

    with subtest("journalbeat should send something to fake loghost"):
      # nc exits successfully when it receives something from journalbeat
      machine.succeed("nc -l 12301")
  '';
})
