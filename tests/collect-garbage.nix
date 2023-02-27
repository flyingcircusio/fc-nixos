import ./make-test-python.nix (
  { pkgs, ... }:

  let
    home = "/home/u0";
    userscan = "${pkgs.fc.userscan}/bin/fc-userscan";
    py = pkgs.python3.interpreter;
    pypkg = pkgs.python3;

  in
  {
    name = "collect-garbage";
    machine =
      { ... }:
      {
        imports = [ ../nixos ../nixos/roles ];

        config = {
          flyingcircus.agent.collect-garbage = true;

          flyingcircus.enc.parameters.interfaces.srv = {
            mac = "52:54:00:12:34:56";
            bridged = false;
            networks = {
              "192.168.101.0/24" = [ "192.168.101.1" ];
              "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::1" ];
            };
            gateways = {};
          };

          users.users.u0 = {
            isNormalUser = true;
            inherit home;
          };
        };
      };

    testScript = ''
      # initial run on empty VM must succeed
      machine.start_job("fc-collect-garbage")
      machine.fail("systemctl is-failed fc-collect-garbage.service")

      # create a script containing a Nix store reference and run
      # fc-collect-garbage again
      print(machine.succeed("""
         set -e
         install -d -o u0 /nix/var/nix/gcroots/per-user/u0
         echo -e "#!${py}\nprint('hello world')" > ${home}/script.py
         chmod +x ${home}/script.py
         grep -r /nix/store/ ${home}
      """))
      machine.start_job("fc-collect-garbage")
      machine.wait_for_file("${home}/.cache/fc-userscan.cache")

      # check that a GC root has been registered
      machine.succeed("ls -lR /nix/var/nix/gcroots/per-user/u0${home} | grep ${pypkg}")
      machine.succeed("test `find /nix/var/nix/gcroots/per-user/u0${home} -type l | wc -l` = 1")
      machine.fail("systemctl is-failed fc-collect-garbage.service")
    '';
  }
)
