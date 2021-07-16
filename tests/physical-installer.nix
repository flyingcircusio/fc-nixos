import ./make-test-python.nix ({ nixpkgs, ... }:
{
  name = "physical-installer";
  machine = 
    { pkgs, ... }:
    { 
      virtualisation.emptyDiskImages = [ 70000 100 ];
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
    machine.succeed("systemctl status lldpd")
    result = machine.succeed("show-interfaces")
    print(result)

    assert result == """\
    INTERFACE           | MAC               | SWITCH               | ADDRESSES
    --------------------+-------------------+----------------------+-----------------------------------
    eth0                | 52:54:00:12:34:56 | None/None            | 10.0.2.15
    eth1                | 52:54:00:12:01:01 | None/None            | 192.168.1.1

    NOTE: If you are missing interface data, wait 30s and run `show-interfaces` again.

    """

    print(machine.succeed("lsblk"))
    print(machine.succeed("fc-secure-erase /dev/vdc"))

    machine.wait_until_tty_matches(1, "nixos@machine")

    machine.screenshot('01boot')

    machine.send_chars("sudo -i\n")
    machine.wait_until_tty_matches(1, "root@machine")

    machine.screenshot('02sudo')

    machine.send_chars("fc-install\n")
    machine.wait_until_tty_matches(1, "52:54:00:12:34:56")
    machine.wait_until_tty_matches(1, "Ready to continue")
    machine.screenshot('03lldp')
    machine.send_chars("\n")

    machine.wait_until_tty_matches(1, "ENC wormhole URL")
    machine.send_chars("file:///tmp/wormhole.json\n")
    machine.screenshot('04wormhole')

    machine.wait_until_tty_matches(1, "Root disk")
    # Erase the default
    for x in "sda":
      machine.send_key("backspace")
    machine.send_chars("vdb\n")
    machine.screenshot('05rootdisk')

    machine.wait_until_tty_matches(1, "Root password:")
    machine.send_chars("asdf\n")
    machine.wait_until_tty_matches(1, "IPMI password:")
    machine.send_chars("asdf2\n")
    machine.screenshot("06passwords")
    machine.wait_until_tty_matches(1, "Wipe whole disk?")

    machine.execute("ln -sf /dev/vdb /dev/disk/by-id/wwn-34789374891")

    machine.send_chars("y\n")
    machine.screenshot("07wipedisk")

    # This is how far I got creating a test. We now would have to create
    # a fake server serving the channel and the nix store... 
    machine.wait_until_tty_matches(1, "error: unable to download")

    machine.screenshot("99finish")


  '';
})
