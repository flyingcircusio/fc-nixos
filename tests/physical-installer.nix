import ./make-test-python.nix (
  { pkgs, lib, ... }:
  let
    outerPkgs = pkgs;
    release = import ../release { };
    channel = release.release.src;
    enc = {
      name = "machine";
      parameters = {
        environment_url = "file://${channel_tarball}";
        interfaces = {
          srv = {
            bridged = false;
            gateways = {
              "10.12.0.0/16" = "10.12.0.1";
            };
            mac = "02:03:00:00:00:07";
            networks = {
              "10.12.0.0/16" = [ "10.12.0.9" ];
            };
          };
          ipmi = {
            networks."192.168.1.0/24" = [ "192.168.1.2" ];
            gateways."192.168.1.0/24" = "192.168.1.1";
            policy = "puppet";
            bridged = false;
          };
        };
      };
    };
    evaled = import "${pkgs.path}/nixos/lib/eval-config.nix" {
      modules = [
        {
          imports = [
            "${channel}/nixos/fc/nixos"
            "${channel}/nixos/fc/nixos/roles"
          ];

          flyingcircus.enc = enc;
          flyingcircus.infrastructureModule = "flyingcircus-physical";

          flyingcircus.agent.updateInMaintenance = false;
          systemd.timers.fc-agent.timerConfig.OnBootSec = "1s";
          boot.loader.grub.device = "/dev/disk/by-id/wwn-34789374891";
          boot.kernelParams = [ "console=ttyS0" ];

          users.users.root.hashedPassword = "$6$YFPbXCROnIKeJEJY$pcndbUot2LPlCs9Y7gMJAbioeDECisxOCOVZU/HB0ImNQzIyuGY//013AHAmNOEUmTEDlQGuGYo3mdxRCL2M3.";

          flyingcircus.boot-style = "efi";
          flyingcircus.infrastructure.fullDiskEncryption.encryptedRoot = true;
        }
      ];
    };

    # tarball only contains symlinks
    channel_tarball = pkgs.runCommand "nixos-channel" { preferLocalBuild = true; } ''
      mkdir -p $out
      cd ${channel.outPath}
      tar cfj $out/nixexprs.tar.bz2 .
    '';

    closureInfo = pkgs.closureInfo {
      rootPaths = [
        evaled.config.system.build.toplevel
        channel
      ];
    };

  in
  {
    name = "physical-installer";
    nodes.machine =
      { config, pkgs, ... }:
      {
        # Don't build documentation that includes options to avoid test failures
        # caused by invalid descriptions or missing defaultText.
        documentation.doc.enable = false;
        documentation.man.enable = false;

        virtualisation.emptyDiskImages = [
          120000
          1100
        ];
        imports = [
          ../nixos
          ../nixos/roles
          "${outerPkgs.path}/nixos/modules/installer/netboot/netboot-minimal.nix"
          ../release/netboot-installer.nix
        ];

        #        virtualisation.useEFIBoot = true;
        #        virtualisation.useBootLoader = true;
        #        virtualisation.memorySize = 6000;
        #        virtualisation.cores = 12;
        virtualisation.diskSize = 4096;

        virtualisation.fileSystems."/mnt/keys" =
          config.flyingcircus.infrastructure.fullDiskEncryption.fsOptions;

        system.activationScripts.dummy_enc =
          let
            dummy_wormhole = pkgs.writers.writeJSON "enc.json" enc;
          in
          ''
            ln -s ${dummy_wormhole} /tmp/wormhole.json
          '';

      };

    testScript = ''
      machine.start(allow_reboot=True)
      machine.wait_for_unit('multi-user.target')

      machine.succeed("ln -sf /dev/vdb /dev/disk/by-id/wwn-34789374891")

      # Provide a Nix database so that nixos-install can copy closures.
      machine.succeed("nix-store --load-db < ${closureInfo}/registration")

      print(machine.execute("cat /proc/cmdline")[1])
      print(machine.execute("ps auxf")[1])
      print(machine.execute("systemctl cat dhcpcd")[1])
      print(machine.execute("cat /nix/store/qadpv1yrn8d73bigcqyicbc15ylq3inj-dhcpcd.conf")[1])

      machine.succeed("systemctl status lldpd")
      result = machine.succeed("show-interfaces")
      print(result)

      #assert result == """\
      #INTERFACE           | MAC               | SWITCH               | ADDRESSES
      #--------------------+-------------------+----------------------+-----------------------------------
      #eth0                | 52:54:00:12:34:56 | None/None            | 10.0.2.15
      #eth1                | 52:54:00:12:01:01 | None/None            |
      #
      #NOTE: If you are missing interface data, wait 30s and run `show-interfaces` again.
      #
      #"""

      with subtest("Initialise keystore"):
      # TODO: this uses the current hostname
        machine.succeed("fc-luks keystore create /dev/vdc > /dev/kmsg 2>&1")
        print(machine.succeed("lsblk"))
        machine.succeed("${pkgs.util-linux}/bin/findmnt /mnt/keys > /dev/kmsg 2>&1")

      machine.wait_until_tty_matches("1", "nixos@machine", timeout=10)

      machine.screenshot('01boot')

      machine.send_chars("sudo -i\n")
      machine.wait_until_tty_matches("1", "root@machine", timeout=10)

      machine.screenshot('02sudo')

      machine.send_chars("NIXOS_INSTALL_ARGS='--substituters \"\" --system ${evaled.config.system.build.toplevel}' PYTHONUNBUFFERED=1 fc-install | tee /dev/kmsg 2>&1\n")
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

      machine.wait_until_tty_matches("1", "LUKS admin key for this location:", timeout=5)
      machine.send_chars("asdf\n")
      machine.wait_until_tty_matches("1", r"Retry otherwise. y\/\[n\]:", timeout=5)
      machine.send_chars("y\n")
      machine.screenshot("06passwords")

      machine.wait_until_tty_matches("1", "No IPMI controller detected", timeout=5)

      machine.screenshot("07noipmi")

      machine.wait_until_tty_matches("1", "Boot style", timeout=5)
      machine.send_chars("efi\n")

      machine.wait_until_tty_matches("1", "Wipe whole disk?", timeout=5)
      machine.send_chars("y\n")

      machine.wait_until_tty_matches("1", "=== Done - reboot at your convenience ===", timeout=300)
      machine.screenshot("99finish")
      # machine.reboot()
    '';
  }
)
