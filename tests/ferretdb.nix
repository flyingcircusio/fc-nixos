import ./make-test-python.nix ({ lib, pkgs, testlib, ... }:
let
  ipv4 = testlib.fcIP.srv4 1;
  ipv6 = testlib.fcIP.srv6 1;

in {
  name = "ferretdb";
  nodes.machine =
    { ... }:
    {
      imports = [
        (testlib.fcConfig { net.fe = false; })
      ];
      flyingcircus.roles.ferretdb.enable = true;
    };


  testScript = { nodes, ... }:
  let
    testJs = pkgs.writeText "test-ferretdb.js" ''
      coll = db.getCollection("test")
      coll.insertOne({test: "helloferret"})
      coll.find({test: "helloferret"}).forEach(printjson)
    '';

    check = ipaddr: ''
    '';

    sensuCheck = testlib.sensuCheckCmd nodes.machine;
  in ''
      machine.wait_for_unit("ferretdb.service")

      with subtest("Ferretdb should respond"):
        machine.wait_until_succeeds('mongosh ${ipv4} --eval db')

      with subtest(f"Inserting and finding a document should work"):
        machine.succeed('mongosh "mongodb://${ipv4}:27017/test" ${testJs} | grep helloferret');

      with subtest("ferretdb sensu check should be green"):
        machine.succeed("${sensuCheck "ferretdb"}")

      with subtest("killing the ferretdb process should trigger an automatic restart"):
        _, out = machine.systemctl("show ferretdb --property MainPID --value")
        previous_pid = int(out.strip())
        machine.succeed("systemctl kill -s KILL ferretdb")
        machine.wait_until_succeeds('test $(systemctl show ferretdb --property NRestarts --value) -eq "1"')
        machine.wait_until_succeeds("${sensuCheck "ferretdb"}")
        _, out = machine.systemctl("show ferretdb --property MainPID --value")
        new_pid = int(out.strip())
        assert new_pid != previous_pid, f"Expected new PID but is still the same: {new_pid}"

      with subtest("ferretdb sensu check should be red after shutting down ferretdb"):
        machine.systemctl("stop ferretdb")
        machine.fail("${sensuCheck "ferretdb"}")
    '';

})
