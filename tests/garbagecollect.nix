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

      # create some files containing Nix store references
      # these should be found & registered by fc-userscan
      print($machine->succeed(<<_EOT_));
        set -e
        echo -e "#!${py}\nprint('hello world')" > ${home}/script.py
        chmod +x ${home}/script.py
        grep -r /nix/store/ ${home}
        sudo -u u0 -- ${userscan} -rvc ${home}/.cache/fc-userscan.cache ${home}
        test -s ${home}/.cache/fc-userscan.cache
        test -n "$(find /nix/var/nix/gcroots/per-user/u0${home} -type l)"
      _EOT_
    '';
  }
)
