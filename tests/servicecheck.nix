import ./make-test-python.nix ({ pkgs, lib, ... }:
{
  name = "servicecheck";

  machine = {
    imports = [ ../nixos ../nixos/roles ];

    flyingcircus.roles.servicecheck.enable = true;

    environment.etc."nixos/enc.json".text = ''
      {"parameters": {"directory_password": "test"}}
    '';

    services.telegraf.enable = false;

    networking.extraHosts = ''
      127.0.0.1 directory.fcio.net
    '';

  };

  testScript = ''
    start_all()
    with subtest("script should try to connect to directory"):
        machine.execute("nc -l 443 -N > /tmp/out &")
        machine.systemctl("start fc-servicecheck")
        machine.succeed("test -s /tmp/out")
  '';
})
