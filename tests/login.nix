import ./make-test-python.nix ({ pkgs, latestKernel ? false, ... }:

{
  name = "login";
  machine =
    { pkgs, lib, config, ... }:
    {
      imports = [
        ../nixos
      ];

      boot.kernelPackages = lib.mkIf latestKernel pkgs.linuxPackages_latest;
    };

  testScript =
    ''
      machine.wait_for_unit('multi-user.target')
      machine.wait_until_succeeds("pgrep -f 'agetty.*tty1'")
      machine.screenshot("postboot")

      with subtest("create user"):
          machine.succeed("useradd -m alice")
          machine.succeed("(echo foobar; echo foobar) | passwd alice")

      # Check whether switching VTs works.
      with subtest("virtual console switching"):
          machine.fail("pgrep -f 'agetty.*tty2'")
          machine.send_key("alt-f2")

          machine.wait_until_succeeds("[ $(fgconsole) = 2 ]")
          machine.wait_for_unit('getty@tty2.service')
          machine.wait_until_succeeds("pgrep -f 'agetty.*tty2'")

      # Log in as alice on a virtual console.
      with subtest("virtual console login"):
          machine.wait_until_tty_matches(2, "login: ")
          machine.send_chars("alice\n")
          machine.wait_until_tty_matches(2, "login: alice")
          machine.wait_until_succeeds("pgrep login")
          machine.wait_until_tty_matches(2, "Password: ")
          machine.send_chars("foobar\n")
          machine.wait_until_succeeds("pgrep -u alice bash")
          machine.send_chars("touch done\n")
          machine.wait_for_file("/home/alice/done")

      # Check whether systemd gives and removes device ownership as
      # needed.
      with subtest("device permissions"):
          machine.succeed("getfacl /dev/snd/timer | grep -q alice")
          machine.send_key("alt-f1")
          machine.wait_until_succeeds("[ $(fgconsole) = 1 ]")
          machine.fail("getfacl /dev/snd/timer | grep -q alice")
          machine.succeed("chvt 2")
          machine.wait_until_succeeds("getfacl /dev/snd/timer | grep -q alice")

      # Log out.
      with subtest("virtual console logout"):
          machine.send_chars("exit\n")
          machine.wait_until_fails("pgrep -u alice bash")
          machine.screenshot("mingetty")

      # Check whether ctrl-alt-delete works.
      with subtest("ctrl-alt-delete"):
          machine.send_key("ctrl-alt-delete")
          machine.wait_for_shutdown
    '';
})
