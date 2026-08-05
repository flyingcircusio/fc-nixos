{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.flyingcircus;
  fclib = config.fclib;
in
mkIf (cfg.infrastructureModule == "flyingcircus-physical") (
  lib.mkMerge [
    {

      hardware.enableRedistributableFirmware = true;
      hardware.cpu.amd.updateMicrocode = true;
      hardware.cpu.intel.updateMicrocode = true;
      flyingcircus.raid.enable = true;
      flyingcircus.networking.physicalHostNetworking = true;

      boot = {
        initrd.availableKernelModules = [
          # assorted network drivers, for hardware discovery during
          # stage 1.
          "3w-9xxx"
          "bnx2"
          "bnxt_en"
          "e1000e"
          "i40e"
          "igb"
          "ixgbe"
          "mlx5_core"
          "mlxfw"
          "tg3"
          # storage drivers, for hardware discovery
          "nvme"
        ];

        # We don't know generally which filesystems our machines use for their
        # /boot partition, so we cannot set this using filesystems.<...>.fsType.
        # We have seen issues that the filesystem could not be mounted
        # (likely because of timing issues), so explicitly load the modules for
        # filesystems we use.
        supportedFilesystems = [
          "ext4"
          "vfat"
        ];
        initrd.supportedFilesystems = [
          "ext4"
          "vfat"
        ];

        # We have seen sporadic boot issues where an ext4 filesystem could not be mounted due to the kernel module not
        # being loaded at mount time.
        # ext4 was an available kernel module then.
        # Until we figured out which bug this is, load ext4 by default in the initrd.
        # PL-135613
        initrd.kernelModules = [
          "ext4"
        ];

        # not relevant for boot stage1
        kernelModules = [
          "dm_mirror" # LVM disk migration scenarios
        ];

        kernelParams = [
          # Drivers
          "dolvm"
          "igb.InterruptThrottleRate=1"
        ];

        kernel.sysctl = {
          # We don't want to allow VMs with routed pub interfaces to
          # be able to connect to e.g. the sshd on the KVM server from
          # within the VRF. This is the kernel default, but we ensure
          # that it's set here correctly anyway. (Compare the
          # corresponding configuration in the router role.)
          "net.ipv4.tcp_l3mdev_accept" = fclib.mkPlatform false;
          "net.ipv4.udp_l3mdev_accept" = fclib.mkPlatform false;
          "vm.swappiness" = fclib.mkPlatform 0;
        };
      };

      flyingcircus.activationScripts = {
        disableSwap = ''
          swapoff -a
          if [[ -e /dev/disk/by-label/swap ]]; then
            wipefs  -af /dev/disk/by-label/swap || true
          fi
        '';
      };
      systemd.targets.swap.enable = false; # implicitly mask the unit to prevent pulling in existing `*.swap` units

      environment.systemPackages = with pkgs; [
        fc.ledtool
        fc.secure-erase
        fc.util-physical
        iperf3
        mstflint
        nvme-cli
        pciutils
        smartmontools
        usbutils
      ];

      fileSystems = {
        "/boot" = {
          device = "/dev/disk/by-label/boot";
          fsType = "auto";
        };
        "/" = {
          device = "/dev/disk/by-label/root";
          fsType = "xfs";
        };
        "/tmp" = {
          device = "/dev/disk/by-label/tmp";
          fsType = "xfs";
          noCheck = true;
        };
      };

      # Not formatting tmp for now because I dont want to refer to it by
      # the filesystem label and some machines use lvm and others dont.

      networking = {
        domain = "fcio.net";
        hostName = fclib.mkPlatform (attrByPath [ "name" ] "default" cfg.enc);
      };

      services.irqbalance.enable = true;

      users.users.root = {
        # Overriden in local.nix
        hashedPassword = fclib.mkPlatform "*";
        openssh.authorizedKeys.keys = attrValues cfg.static.adminKeys;
      };

      powerManagement.cpuFreqGovernor = "performance";

      services.lldpd.enable = true;

      systemd.services.lldp-intel-bug-126553 = {
        wantedBy = [ "multi-user.target" ];
        before = [ "lldpd.service" ];
        serviceConfig.Type = "oneshot";
        serviceConfig.RemainAfterExit = true;
        script = ''
          if [ -d /sys/kernel/debug/i40e ]; then
            for f in /sys/kernel/debug/i40e/*/command; do
              echo lldp stop > $f
            done
          fi
        '';
      };

      services.journald.extraConfig = ''
        SystemMaxUse=8G
        MaxLevelConsole=err
        ForwardToWall=no
      '';

      systemd.services.lvm-upgrade-metadata = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.Type = "oneshot";
        serviceConfig.RemainAfterExit = true;
        script = ''
          set -e
          vgs=$(${pkgs.lvm2.bin}/bin/vgs --reportformat=json 2>/dev/null |
            ${pkgs.jq}/bin/jq --raw-output '.report[0].vg[] | .vg_name')
          for vg in $vgs; do
            echo $vg;
            ${pkgs.lvm2.bin}/bin/vgck --updatemetadata $vg;
          done
        '';
      };

      # PL-133421: some hardware+kernel combinations don't seem to
      # deconfigure USB devices properly at shutdown time, which can
      # lead to devices getting stuck and then failing to reappear on
      # the bus after a reboot. unloading the driver in late shutdown
      # before userland ends avoids this problem.
      systemd.shutdown."unload-xhci-driver.shutdown" = pkgs.writeShellScript "rmmod-xhci" ''
        ${pkgs.kmod}/bin/modprobe -v -r xhci_pci
      '';

      flyingcircus.ipmi.enable = true;

      flyingcircus.passwordlessSudoPackages = [
        {
          commands = [
            "bin/check_interfaces"
            "bin/check_lvm_integrity"
          ];
          package = pkgs.fc.sensuplugins;
          groups = [ "sensuclient" ];
        }
      ];

      flyingcircus.services.sensu-client.checks = with pkgs; {
        interfaces = {
          notification = "Network interfaces are healthy";
          command =
            "sudo ${fc.sensuplugins}/bin/check_interfaces "
            + (lib.concatMapStringsSep " " (
              link: "-i ${link.link},${toString link.minimumPortSpeed}:"
            ) cfg.networking.monitorLinks);
          interval = 60;
        };
        lvm_integrity = {
          notification = "LVM integrity is intact";
          command = "sudo ${fc.sensuplugins}/bin/check_lvm_integrity -v -c 1";
        };
      };

      # PL-130846 Temporary fix until having Nix >= 2.4:
      # Ensure there are enough build users available to fulfill `maxJobs`, which is
      # automatically set to the number of cores. Our largest machines currently have
      # 128 core-threads.
      nix.nrBuildUsers = 128;

    }

    (lib.mkIf (config.flyingcircus.boot-style == "bios") {
      boot.loader.grub = {
        device = fclib.mkPlatform "/dev/sda";
        fsIdentifier = "provided";
        extraConfig = ''
          # `console` output is sufficiently forwarded through IPMI SOL and even
          # shows up on the graphics output as well.
          # No need to configure the `serial` grub IO
          terminal_output console
          terminal_input console
        '';
      };
    })

    (lib.mkIf (config.flyingcircus.boot-style == "efi") {
      boot.loader = {
        systemd-boot.enable = true;
        efi.canTouchEfiVariables = true;
      };
    })

  ]
)
