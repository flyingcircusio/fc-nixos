import ./make-test.nix ({ version ? "4.0", lib, pkgs, ... }:
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
          networks = {
            "192.168.101.0/24" = [ ipv4 ];
            "2001:db8:f030:1c3::/64" = [ ipv6 ];
          };
          gateways = {};
        };
      };
    };


  testScript =
  let
    testJs = pkgs.writeText "test-mongo.js" ''
      coll = db.getCollection("test")
      coll.insertOne({test: "hellomongo"})
      coll.find({test: "hellomongo"}).forEach(printjson)
    '';

    check = ipaddr: ''
      $machine->succeed('mongo --ipv6 ${ipaddr}:27017/test ${testJs} | grep hellomongo');
    '';

  in ''
      $machine->waitForUnit("mongodb.service");
      # Check if we are using the correct version.
      $machine->succeed("systemctl show mongodb --property ExecStart --value | grep -q mongodb-${version}");
      $machine->waitForOpenPort(27017);
      $machine->waitUntilSucceeds('mongo --eval db');
    '' + lib.concatMapStringsSep "\n" check [ "127.0.0.1" "[::1]" ipv4 "[${ipv6}]" ]
    + ''
      # service user should be able to write to local config dir
      $machine->succeed('sudo -u mongodb touch /etc/local/mongodb/mongodb.yaml');
    '';

})
