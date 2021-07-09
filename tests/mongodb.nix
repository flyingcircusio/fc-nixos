import ./make-test-python.nix ({ version ? "4.0", lib, pkgs, testlib, ... }:
let
  ipv4 = "192.168.101.1";
  ipv6 = "2001:db8:f030:1c3::1";
  rolename = "mongodb${lib.replaceStrings ["."] [""] version}";

in {
  name = "mongodb";
  machine =
    { ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
      flyingcircus.roles.${rolename}.enable = true;

      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:34:56";
          bridged = false;
          networks = {
            "192.168.101.0/24" = [ ipv4 ];
            "2001:db8:f030:1c3::/64" = [ ipv6 ];
          };
          gateways = {};
        };
      };
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
    ''
    + lib.optionalString (version != "3.2") ''
        with subtest("mongodb feature compat check should be green"):
            machine.succeed("${sensuCheck "mongodb_feature_compat_version"}")
    ''
    + ''
      with subtest("mongodb sensu check should be red after shutting down mongodb"):
        machine.systemctl("stop mongodb")
        machine.fail("${sensuCheck "mongodb"}")

      with subtest("mongodb restarts on crash"):
        machine.systemctl("start mongodb")
        machine.wait_for_unit("mongodb.service")
        _, out = machine.execute('pgrep mongod')
        print(out)
        previous_pid = int(out.strip())
        machine.succeed("killall -11 mongod")
        import time
        time.sleep(5)
        machine.wait_for_unit("mongodb.service")
        machine.succeed("systemctl show mongodb | grep ActiveState=active")
        _, out = machine.execute('pgrep mongod')
        new_pid = int(out.strip())
        print("new pid:", new_pid, "old pid:", previous_pid)
        assert new_pid != previous_pid;
    '';

})
