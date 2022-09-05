import ./make-test-python.nix ({ testlib, ... }:
{
  name = "syslog";
  testCases = {

    plain = {
      nodes = {
        machine =
          { ... }:
          {
            imports = [ (testlib.fcConfig {}) ];
          };
        };

      testScript = ''
        with subtest("rsyslogd should not run in default config"):
          machine.fail("systemctl status syslog")
      '';
    };

    extraRules =
      let extraRule = ''local2.info action(type="omfwd" target="localhost" port="5140" protocol="udp")'';
     in {

      nodes = {
        machine =
          { ... }:
          {
            imports = [ (testlib.fcConfig {}) ];
            flyingcircus.syslog.extraRules = extraRule;
          };
        };

      testScript = ''
        machine.wait_for_unit("syslog.service")

        with subtest("syslog config should have extra rules"):
          config = machine.succeed("syslog-show-config")
          assert '${extraRule}' in config, "expected extra config line not found"
      '';
    };

    separateFacilities = {
      nodes = {
        machine =
          { ... }:
          {
            imports = [ (testlib.fcConfig {}) ];
            flyingcircus.syslog.separateFacilities = {
              local2 = "/var/log/test.log";
            };
          };
        };

      testScript = ''
        machine.wait_for_unit("syslog.service")

        with subtest("logging to separate facility via UDP should go to logfile"):
          machine.succeed("logger -p local2.info -h localhost TEST_LOCAL2_INFO")
          machine.wait_until_succeeds("grep TEST_LOCAL2_INFO /var/log/test.log")
      '';
    };

  };
})
