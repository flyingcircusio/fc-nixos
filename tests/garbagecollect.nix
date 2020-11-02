import ./make-test.nix (
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
      $machine->startJob("fc-collect-garbage");
      $machine->fail("systemctl is-failed fc-collect-garbage.service");

      # create a script containing a Nix store reference and run
      # fc-collect-garbage again
      print($machine->succeed(<<_EOT_));
        set -e
        echo -e "#!${py}\nprint('hello world')" > ${home}/script.py
        chmod +x ${home}/script.py
        grep -r /nix/store/ ${home}
      _EOT_
      $machine->startJob("fc-collect-garbage");
      print($machine->waitForFile("${home}/.cache/fc-userscan.cache"));

      # check that a GC root has been registered
      print($machine->succeed(<<_EOT_));
        ls -lR /nix/var/nix/gcroots/per-user/u0${home} | grep ${py}
        test `find /nix/var/nix/gcroots/per-user/u0${home} -type l | wc -l` = 1
      _EOT_
      $machine->fail("systemctl is-failed fc-collect-garbage.service");
    '';
  }
)
