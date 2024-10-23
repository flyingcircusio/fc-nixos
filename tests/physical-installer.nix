import ./make-test-python.nix ({ nixpkgs, ... }:
{
  name = "physical-installer";
  machine =
    { pkgs, config, ... }:
    {
      virtualisation.emptyDiskImages = [ 120000 100 ];
      imports = [
        "${nixpkgs}/nixos/modules/installer/netboot/netboot-minimal.nix"
        ../release/netboot-installer.nix
      ];

      system.activationScripts.dummy_enc = let
        dummy_wormhole = pkgs.writeText "enc.json" ''
          {"parameters": {"environment_url": "http://asdf" } }
        ''; in
        ''
          ln -s ${dummy_wormhole} /tmp/wormhole.json
        '';

    };

  testScript = ''
    machine.wait_for_unit('multi-user.target')

    print(machine.execute("cat /proc/cmdline")[1])
    print(machine.execute("ps auxf")[1])
    print(machine.execute("systemctl cat dhcpcd")[1])
    print(machine.execute("cat /nix/store/qadpv1yrn8d73bigcqyicbc15ylq3inj-dhcpcd.conf")[1])

    machine.succeed("systemctl status lldpd")
    result = machine.succeed("show-interfaces")
    print(result)

    assert result == """\
    INTERFACE           | MAC               | SWITCH               | ADDRESSES
    --------------------+-------------------+----------------------+-----------------------------------
    eth0                | 52:54:00:12:34:56 | None/None            | 10.0.2.15
    eth1                | 52:54:00:12:01:01 | None/None            | 

    NOTE: If you are missing interface data, wait 30s and run `show-interfaces` again.

    """


    # In 24.05 wait_until_tty_matches has a timeout argument, but 21.05 doesn't
    # this can be refactored once we update.
    TIMEOUT=900

    def retry(fn: Callable) -> None:
        """Call the given function repeatedly, with 1 second intervals,
        until it returns True or a timeout is reached.
        """
        global TIMEOUT
        for _ in range(TIMEOUT):
            if fn(False):
                return
            time.sleep(1)

        if not fn(True):
            raise Exception("action timed out")

    import sys
    sys.modules[machine.__module__].retry = retry

    print(machine.succeed("lsblk"))
    print(machine.succeed("fc-secure-erase /dev/vdc"))

    TIMEOUT=10
    machine.wait_until_tty_matches(1, "nixos@machine")

    machine.screenshot('01boot')

    machine.send_chars("sudo -i\n")
    machine.wait_until_tty_matches(1, "root@machine")

    machine.screenshot('02sudo')

    TIMEOUT=5
    machine.send_chars("fc-install\n")
    machine.wait_until_tty_matches(1, "52:54:00:12:34:56")
    machine.wait_until_tty_matches(1, "Ready to continue")
    machine.screenshot('03lldp')
    machine.send_chars("\n")

    machine.wait_until_tty_matches(1, "ENC wormhole URL")
    machine.send_chars("file:///tmp/wormhole.json\n")
    machine.screenshot('04wormhole')

    machine.wait_until_tty_matches(1, "Root disk")
    machine.send_chars("/dev/vdb\n")
    machine.screenshot('05rootdisk')

    machine.wait_until_tty_matches(1, "Root password:")
    machine.send_chars("asdf\n")
    machine.screenshot("06passwords")

    machine.wait_until_tty_matches(1, "No IPMI controller detected")

    machine.screenshot("07noipmi")

    machine.wait_until_tty_matches(1, "Boot style")
    machine.send_chars("efi\n")

    machine.wait_until_tty_matches(1, "Wipe whole disk?")

    machine.execute("ln -sf /dev/vdb /dev/disk/by-id/wwn-34789374891")
    machine.send_chars("y\n")

    TIMEOUT=30

    # This is how far I got creating a test. We now would have to create
    # a fake server serving the channel and the nix store...
    machine.wait_until_tty_matches(1, "error: unable to download")

    machine.screenshot("99finish")

  '';
})
