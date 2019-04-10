{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.flyingcircus;

in
mkIf (cfg.infrastructureModule == "flyingcircus") {

  nix.extraOptions = ''
    http-connections = 2
  '';

  boot = {
    consoleLogLevel = mkDefault 7;

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
    fc.box
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

  flyingcircus = {
    agent.collect-garbage = true;
    logrotate.enable = true;
  };

  networking = {
    domain = "fcio.net";
    hostName = mkDefault (attrByPath [ "name" ] "default" cfg.enc);
  };

  swapDevices = [ { device = "/dev/disk/by-label/swap"; } ];

  security.dhparams.enable = true;
  security.wrappers.box.source = "${pkgs.fc.box}/bin/box";

  services = {

    qemuGuest.enable = true;
    openssh.challengeResponseAuthentication = false;
    openssh.passwordAuthentication = false;
    telegraf.enable = mkDefault true;

    timesyncd.servers =
      let
        loc = attrByPath [ "parameters" "location" ] "" cfg.enc;
      in
      attrByPath [ "static" "ntpServers" loc ] [ "pool.ntp.org" ] cfg;

    # installs /dev/disk/device-by-alias/*
    udev.extraRules = ''
      # Select GRUB boot device
      SUBSYSTEM=="block", KERNEL=="[vs]da", SYMLINK+="disk/device-by-alias/root"
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
      attrValues cfg.static.adminKeys;
  };

}
