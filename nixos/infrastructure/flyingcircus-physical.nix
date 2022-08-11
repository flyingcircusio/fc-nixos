{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.flyingcircus;
in
mkIf (cfg.infrastructureModule == "flyingcircus-physical") {

    hardware.enableRedistributableFirmware = true;
    hardware.cpu.amd.updateMicrocode = true;
    hardware.cpu.intel.updateMicrocode = true;
    flyingcircus.raid.enable = true;

    boot = {

      kernelParams = [
        # Drivers
        "dolvm"
        "ipmi_watchdog.timeout=60"
        "igb.InterruptThrottleRate=1"
        "ixgbe.InterruptThrottleRate=1"
      ];

      loader.grub = {
        device = config.fclib.mkPlatform "/dev/sda";
        fsIdentifier = "provided";
        gfxmodeBios = "text";
      };

      # Wanted by backy and Ceph servers
      kernel.sysctl."vm.vfs_cache_pressure" = 10;

    };

    environment.systemPackages = with pkgs; [
      fc.secure-erase
      fc.util-physical
      mstflint
      pciutils
      smartmontools
      usbutils
    ];

    fileSystems = {
      "/boot" = {
        device = "/dev/disk/by-label/boot";
        fsType = "ext4";
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

    networking = {
      domain = "fcio.net";
      hostName = config.fclib.mkPlatform (attrByPath [ "name" ] "default" cfg.enc);
    };

    # Not perfect but avoids triggering the 'established' rule which can
    # lead to massive/weird Ceph instabilities.
    networking.firewall.trustedInterfaces = [ "ethsto" "ethstb" ];

    swapDevices = [ { device = "/dev/disk/by-label/swap"; } ];

    users.users.root = {
      # Overriden in local.nix
      hashedPassword = config.fclib.mkPlatform "*";
      openssh.authorizedKeys.keys =
        attrValues cfg.static.adminKeys;
    };

    powerManagement.cpuFreqGovernor = "ondemand";

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

    flyingcircus.ipmi.enable = true;

    flyingcircus.passwordlessSudoRules = [
      {
        commands = with pkgs; [
          "${fc.sensuplugins}/bin/check_interfaces"
          "${fc.sensuplugins}/bin/check_lvm_integrity"
        ];
        groups = [ "sensuclient" ];
      }
    ];

    flyingcircus.services.sensu-client.checks = with pkgs; {
      interfaces = {
        notification = "Network interfaces are healthy";
        command = "sudo ${fc.sensuplugins}/bin/check_interfaces -a -s 1000:";
        interval = 60;
      };
      lvm_integrity = {
        notification = "LVM integrity is intact";
        command = "sudo ${fc.sensuplugins}/bin/check_lvm_integrity -v -c 1";
      };
    };

}
