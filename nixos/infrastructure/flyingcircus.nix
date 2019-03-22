{ config, lib, pkgs, ... }:

with lib;
mkIf (config.flyingcircus.infrastructureModule == "flyingcircus") {

  nix.extraOptions = ''
    http-connections = 2
  '';

  boot = {
    consoleLogLevel = 7;

    initrd.kernelModules = [
      "i6300esb"
      "virtio_blk"
      "virtio_console"
      "virtio_net"
      "virtio_pci"
      "virtio-rng"
      "virtio_scsi"
    ];

    kernelParams = [
      # Crash management
      "panic=1"
      "boot.panic_on_fail"

      # Output management
      "console=ttyS0"
      "systemd.journald.forward_to_console=no"
      "systemd.log_target=kmsg"
      "nosetmode"
    ];

    loader.grub = {
      device = "/dev/disk/device-by-alias/root";
      fsIdentifier = "provided";
      gfxmodeBios = "text";
    };

    kernel.sysctl."vm.swappiness" = mkDefault 10;
  };

  environment.systemPackages = with pkgs; [
    #fc.box  # XXX
    fc.userscan
  ];

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

  flyingcircus.quota.enable = true;

  networking = {
    domain = "fcio.net";
    hostName = attrByPath [ "name" ] "default" config.flyingcircus.enc;
  };

  swapDevices = [ { device = "/dev/disk/by-label/swap"; } ];

  # XXX doesn't work anymore -- switch to security.wrappers
  #security.setuidPrograms = [ "box" ];

  services = {
    qemuGuest.enable = true;

    openssh.passwordAuthentication = false;

    # installs /dev/disk/device-by-alias/*
    udev.extraRules = ''
      # Select GRUB boot device
      SUBSYSTEM=="block", KERNEL=="[vs]da", SYMLINK+="disk/device-by-alias/root"
    '';

    timesyncd.servers = [ "pool.ntp.org" ]; # XXX ENC NTP servers
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
        Unit = "serial-console-liveness.service";
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
    initialHashedPassword = "*";
    openssh.authorizedKeys.keys =
      attrValues config.flyingcircus.static.adminKeys;
  };

}
