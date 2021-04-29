{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.flyingcircus;
  ioScheduler =  if (cfg.infrastructure.preferNoneSchedulerOnSsd && (cfg.enc.parameters.rbd_pool == "rbd.ssd"))
                 then "none"
                 else "bfq";
in
mkIf (cfg.infrastructureModule == "flyingcircus") {
 
  boot = {
    initrd.kernelModules = [
      "virtio_blk"
      "virtio_console"
      "virtio_net"
      "virtio_pci"
      "virtio_rng"
      "virtio_scsi"
      "i6300esb"
    ];

    kernelParams = [
      "console=ttyS0"
      "nosetmode"
    ];

    loader.grub = {
      device = "/dev/disk/device-by-alias/root";
      fsIdentifier = "provided";
      gfxmodeBios = "text";
    };
  };

  fileSystems = {
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

  swapDevices = [ { device = "/dev/disk/by-label/swap"; } ];

  services = {
    qemuGuest.enable = true;

    udev.extraRules = ''
      # GRUB boot device should be device-by-alias/root
      SUBSYSTEM=="block", KERNEL=="vda", SYMLINK+="disk/device-by-alias/root"
      SUBSYSTEM=="block", ACTION=="add|change", KERNEL=="vd[a-z]", ATTR{queue/scheduler}="${ioScheduler}", ATTR{queue/rotational}="0"
    '';
  };

  systemd = {
    ctrlAltDelUnit = "poweroff.target";
    extraConfig = ''
      RuntimeWatchdogSec=60
    '';

    timers.serial-console-liveness = {
      description = "Timer for Serial console liveness marker";
      requiredBy = [ "serial-getty@ttyS0.service" ];
      timerConfig = {
        OnBootSec = "10m";
        OnUnitActiveSec = "10m";
      };
    };

    services.serial-console-liveness = {
      description = "Serial console liveness marker";
      serviceConfig.Type = "oneshot";
      script = "echo \"$(date) -- SERIAL CONSOLE IS LIVE --\" > /dev/ttyS0";
    };
  };

  users.users.root = {
    hashedPassword = "*";
    openssh.authorizedKeys.keys =
      attrValues cfg.static.adminKeys;
  };


}
