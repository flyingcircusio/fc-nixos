{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.flyingcircus;
  telegrafShowConfig = pkgs.writeScriptBin "telegraf-show-config" ''
    cat $(systemctl cat telegraf | grep "ExecStart=" | cut -d" " -f3 | tr -d '"')
  '';

in
mkIf (cfg.infrastructureModule == "flyingcircus") {

  nix.extraOptions = ''
    http-connections = 2
  '';

  boot = {
    consoleLogLevel = mkDefault 7;

    initrd.kernelModules = [
      "bfq"
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

    kernel.sysctl."vm.swappiness" = mkDefault 1;
  };

  environment.systemPackages = with pkgs; [
    fc.userscan
    telegrafShowConfig
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

    udev.extraRules = ''
      # GRUB boot device should be device-by-alias/root
      SUBSYSTEM=="block", KERNEL=="vda", SYMLINK+="disk/device-by-alias/root"
      # Use BFQ for better fairness
      SUBSYSTEM=="block", ACTION=="add|change", KERNEL=="vd[a-z]", ATTR{queue/scheduler}="bfq", ATTR{queue/rotational}="0"
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
    initialHashedPassword = "*";
    openssh.authorizedKeys.keys =
      attrValues cfg.static.adminKeys;
  };

}
