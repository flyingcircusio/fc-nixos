import ./make-test-python.nix ({ version ? "4.2", lib, pkgs, testlib, ... }:
let
  ipv4 = testlib.fcIP.srv4 1;
  ipv6 = testlib.fcIP.srv6 1;
  rolename = "mongodb${lib.replaceStrings ["."] [""] version}";

in {
  name = "mongodb";
  nodes.machine =
    { ... }:
    {
      imports = [
        (testlib.fcConfig { net.fe = false; })
      ];
      flyingcircus.roles.${rolename}.enable = true;
      flyingcircus.allowedUnfreePackageNames = ["mongodb"];
    };


  testScript = { nodes, ... }:
  let
    testJs = pkgs.writeText "test-mongo.js" ''
      coll = db.getCollection("test")
      coll.insertOne({test: "hellomongo"})
      coll.find({test: "hellomongo"}).forEach(printjson)
    '';

    check = ipaddr: ''
      with subtest(f"connect to ${ipaddr}"):
        machine.succeed('mongo --ipv6 ${ipaddr}:27017/test ${testJs} | grep hellomongo');
    '';

    sensuCheck = testlib.sensuCheckCmd nodes.machine;
  in ''
      machine.wait_for_unit("mongodb.service")
      machine.wait_for_open_port(27017)
      machine.wait_until_succeeds('mongo --eval db')
      with subtest("Check if we are using the correct version"):
        machine.succeed("systemctl show mongodb --property ExecStart --value | grep -q mongodb-${version}")
    '' + lib.concatMapStringsSep "\n" check [ "127.0.0.1" "[::1]" ipv4 "[${ipv6}]" ]
    + ''
      with subtest("service user should be able to write to local config dir"):
        machine.succeed('sudo -u mongodb touch /etc/local/mongodb/mongodb.yaml')

      with subtest("mongodb sensu check should be green"):
        machine.succeed("${sensuCheck "mongodb"}")

    '' + lib.optionalString (lib.versionAtLeast version "3.4") ''
      with subtest("(3.4+) mongodb feature compat check should be green"):
          machine.succeed("${sensuCheck "mongodb_feature_compat_version"}")
    ''
    + ''
      with subtest("killing the opensearch process should trigger an automatic restart"):
        _, out = machine.systemctl("show mongodb --property MainPID --value")
        previous_pid = int(out.strip())
        machine.succeed("systemctl kill -s KILL mongodb")
        machine.wait_until_succeeds('test $(systemctl show mongodb --property NRestarts --value) -eq "1"')
        machine.wait_until_succeeds("${sensuCheck "mongodb"}")
        _, out = machine.systemctl("show mongodb --property MainPID --value")
        new_pid = int(out.strip())
        assert new_pid != previous_pid, f"Expected new PID but is still the same: {new_pid}"

      with subtest("mongodb sensu check should be red after shutting down mongodb"):
        machine.systemctl("stop mongodb")
        machine.fail("${sensuCheck "mongodb"}")
    '';

})
