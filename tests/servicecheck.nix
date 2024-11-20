import ./make-test-python.nix ({ pkgs, lib, testlib, ... }:
{
  name = "servicecheck";

  nodes.machine = {
    imports = [
      (testlib.fcConfig {
        id = 1;
        extraEncParameters = {
          directory_password = "test";
        };
      })
    ];

    flyingcircus.roles.servicecheck.enable = true;

    networking.extraHosts = ''
      127.0.0.1 directory.fcio.net
    '';

  };

  testScript = ''
    start_all()
    with subtest("script should try to connect to directory"):
        machine.execute("nc -l 443 -N > /tmp/out &")
        machine.systemctl("start fc-servicecheck")
        machine.wait_until_succeeds("test -s /tmp/out")
  '';
})
