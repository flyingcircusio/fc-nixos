import ./make-test-python.nix ({ testlib, ... }:
{
  name = "journalbeat";
  nodes = {
    machine =
      { ... }:
      {
        imports = [ (testlib.fcConfig {}) ];

        flyingcircus.journalbeat.logTargets = {
          "localhost" = {
            host = "localhost";
            port = 12301;
          };
        };
      };
    };

  testScript = ''
    machine.wait_for_unit("filebeat-journal-localhost.service")

    with subtest("filebeat should send something to fake loghost"):
      # nc exits successfully when it receives something from filebeat
      machine.succeed("nc -l 12301 > /dev/null")
  '';
})
