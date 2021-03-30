import ./make-test-python.nix (
  { pkgs, ... }:

  let
    home = "/home/u0";
    userscan = "${pkgs.fc.userscan}/bin/fc-userscan";
    py = pkgs.python3.interpreter;

  in
  {
    name = "garbagecollect";
    machine =
      { ... }:
      {
        imports = [ ../nixos ];

        config = {
          flyingcircus.agent.collect-garbage = true;

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
      print(machine.wait_for_file("${home}/.cache/fc-userscan.cache"))

      # check that a GC root has been registered
      print(machine.succeed("""
        ls -lR /nix/var/nix/gcroots/per-user/u0${home} | grep ${py}
        test `find /nix/var/nix/gcroots/per-user/u0${home} -type l | wc -l` = 1
      """))
      machine.fail("systemctl is-failed fc-collect-garbage.service")
    '';
  }
)
