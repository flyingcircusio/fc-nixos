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
      initrd.availableKernelModules = [
        # assorted network drivers, for hardware discovery during
        # stage 1.
        "e1000e"
        "i40e"
        "mlxfw"
        "tg3"
        "mlx5_core"
        "bnxt_en"
        "igb"
        "ixgbe"
        "bnx2"
      ];

      kernelParams = [
        # Drivers
        "dolvm"
        "igb.InterruptThrottleRate=1"
      ];

      loader.grub = {
        device = config.fclib.mkPlatform "/dev/sda";
        fsIdentifier = "provided";
        gfxmodeBios = "text";
      };

      # Wanted by backy and Ceph servers
      kernel.sysctl."vm.vfs_cache_pressure" = 10;

      kernel.sysctl."vm.swappiness" = config.fclib.mkPlatform 0;

    };

    flyingcircus.activationScripts = {
      disableSwap = ''
        swapoff -a
        wipefs -af /dev/disk/by-label/swap || true
      '';
    };
    systemd.targets.swap.enable = false;  # implicitly mask the unit to prevent pulling in existing `*.swap` units

    environment.systemPackages = with pkgs; [
      fc.ledtool
      fc.secure-erase
      fc.util-physical
      mstflint
      nvme-cli
      pciutils
      smartmontools
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

    boot.kernel.sysctl = {

      "vm.min_free_kbytes" = "513690";

      "net.core.netdev_max_backlog" = "300000";
      "net.core.optmem" = "40960";
      "net.core.wmem_default" = "16777216";
      "net.core.wmem_max" = "16777216";
      "net.core.rmem_default" = "8388608";
      "net.core.rmem_max" = "16777216";
      "net.core.somaxconn" = "1024";

      "net.ipv4.tcp_fin_timeout" = "10";
      "net.ipv4.tcp_max_syn_backlog" = "30000";
      "net.ipv4.tcp_slow_start_after_idle" = "0";
      "net.ipv4.tcp_syncookies" = "0";
      "net.ipv4.tcp_timestamps" = "0";
                                  # 1MiB   8MiB    # 16 MiB
      "net.ipv4.tcp_wmem" = "1048576 8388608 16777216";
      "net.ipv4.tcp_wmem" = "1048576 8388608 16777216";
      "net.ipv4.tcp_mem" = "1048576 8388608 16777216";

      "net.ipv4.tcp_tw_recycle" = "1";
      "net.ipv4.tcp_tw_reuse" = "1";

      # Supposedly this doesn't do much good anymore, but in one of my tests
      # (too many, can't prove right now.) this appeared to have been helpful.
      "net.ipv4.tcp_low_latency" = "1";

      # Optimize multi-path for VXLAN (layer3 in layer3)
      "net.ipv4.fib_multipath_hash_policy" = "2";
    };

    services.irqbalance.enable = true;

    # Not perfect but avoids triggering the 'established' rule which can
    # lead to massive/weird Ceph instabilities. Also, coordination tasks
    # like Qemu migrations run over ethmgm want to be trusted.
    networking.firewall.trustedInterfaces = [ "ethsto" "ethstb" "ethmgm" ];

    users.users.root = {
      # Overriden in local.nix
      hashedPassword = config.fclib.mkPlatform "*";
      openssh.authorizedKeys.keys =
        attrValues cfg.static.adminKeys;
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

    # PL-130846 Temporary fix until having Nix >= 2.4:
    # Ensure there are enough build users available to fulfill `maxJobs`, which is
    # automatically set to the number of cores. Our largest machines currently have
    # 128 core-threads.
    nix.nrBuildUsers = 128;

}
