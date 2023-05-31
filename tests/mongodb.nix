import ./make-test-python.nix ({ version ? "4.2", lib, pkgs, testlib, ... }:
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

      with subtest("mongodb feature compat check should be green"):
          machine.succeed("${sensuCheck "mongodb_feature_compat_version"}")

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
