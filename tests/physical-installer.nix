import ./make-test-python.nix (
  { pkgs, ... }:
  let
    outerPkgs = pkgs;
  in
  {
    name = "physical-installer";
    nodes.machine =
      { pkgs, ... }:
      {
        # Don't build documentation that includes options to avoid test failures
        # caused by invalid descriptions or missing defaultText.
        documentation.doc.enable = false;
        documentation.man.enable = false;

        virtualisation.emptyDiskImages = [
          120000
          100
        ];
        imports = [
          "${outerPkgs.path}/nixos/modules/installer/netboot/netboot-minimal.nix"
          ../release/netboot-installer.nix
        ];

        system.activationScripts.dummy_enc =
          let
            dummy_wormhole = pkgs.writeText "enc.json" ''
              {"parameters": {"environment_url": "http://asdf" } }
            '';
          in
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

      print(machine.succeed("lsblk"))
      print(machine.succeed("fc-secure-erase /dev/vdc"))

      machine.wait_until_tty_matches("1", "nixos@machine", timeout=10)

      machine.screenshot('01boot')

      machine.send_chars("sudo -i\n")
      machine.wait_until_tty_matches("1", "root@machine", timeout=10)

      machine.screenshot('02sudo')

      machine.send_chars("fc-install\n")
      machine.wait_until_tty_matches("1", "52:54:00:12:34:56", timeout=5)
      machine.wait_until_tty_matches("1", "Ready to continue", timeout=5)
      machine.screenshot('03lldp')
      machine.send_chars("\n")

      machine.wait_until_tty_matches("1", "ENC wormhole URL", timeout=5)
      machine.send_chars("file:///tmp/wormhole.json\n")
      machine.screenshot('04wormhole')

      machine.wait_until_tty_matches("1", "Root disk", timeout=5)
      machine.send_chars("/dev/vdb\n")
      machine.screenshot('05rootdisk')

      machine.wait_until_tty_matches("1", "Root password:", timeout=5)
      machine.send_chars("asdf\n")
      machine.screenshot("06passwords")

      machine.wait_until_tty_matches("1", "No IPMI controller detected", timeout=5)

      machine.screenshot("07noipmi")

      machine.wait_until_tty_matches("1", "Boot style", timeout=5)
      machine.send_chars("efi\n")

      machine.wait_until_tty_matches("1", "Wipe whole disk?", timeout=5)

      machine.execute("ln -sf /dev/vdb /dev/disk/by-id/wwn-34789374891")
      machine.send_chars("y\n")

      # This is how far I got creating a test. We now would have to create
      # a fake server serving the channel and the nix store...
      machine.wait_until_tty_matches("1", "error: unable to download", timeout=30)

      machine.screenshot("99finish")

    '';
  }
)
