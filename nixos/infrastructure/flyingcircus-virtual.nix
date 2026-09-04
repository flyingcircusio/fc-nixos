{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  inherit (config) fclib;
  cfg = config.flyingcircus;
  ioScheduler =
    if (cfg.infrastructure.preferNoneSchedulerOnSsd && (cfg.enc.parameters.rbd_pool == "rbd.ssd")) then
      "none"
    else
      "bfq";
  maxIops = attrByPath [ "parameters" "iops" ] 250 cfg.enc;
  agentThrottling = weight: {
    # device-specific override for the default `IOWeight`
    IODeviceWeight = "/dev/vda ${toString weight}";
  };

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

    kernel.sysctl = {
      # Don't suppress hung task warnings in dmesg, as this hides
      # useful debugging information.
      "kernel.hung_task_warnings" = -1;
    };

    loader.grub = {
      device = "/dev/disk/device-by-alias/root";
      fsIdentifier = "provided";
      extraConfig = ''
        # output goes to serial such that qemu can log it
        terminal_output serial_com0
        # keep console input though to be able to control grub via keypresses passed in via VNC
        terminal_input console
      '';
    };
  };

  flyingcircus.hostRgwAddress =
    let
      # We allow VMs to talk to their KVM host's radosgw proxy to provide them
      # with fast storage access.
      hostRgwServices = fclib.findServices "kvm_host-local-rgw";
      hostmap = lib.listToAttrs (
        map (s: lib.nameValuePair (head (lib.splitString "." s.address)) (head s.ips)) hostRgwServices
      );

      kvmHost = config.flyingcircus.enc.parameters.kvm_host or "none";
    in
    hostmap."${kvmHost}" or null;

  flyingcircus.journalbeat.fields =
    let
      encParams = [
        "cores"
        "disk"
        "environment"
        "iops"
        "kvm_host"
        "memory"
        "production"
        "rbd_pool"
      ];
    in
    lib.optionalAttrs (cfg.enc ? "parameters") (
      lib.filterAttrs (n: v: v != null) (
        lib.listToAttrs (
          map (name: lib.nameValuePair name (cfg.enc.parameters."${name}" or null)) encParams
        )
      )
    );

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/root";
      fsType = "xfs";
    };
    "/tmp" = {
      device = "/dev/disk/by-partlabel/tmp";
      fsType = "xfs";
      noCheck = true;
    };
  };

  swapDevices = [ { device = "/dev/disk/by-label/swap"; } ];

  systemd.oomd = {
    enableSystemSlice = true;
    enableUserSlices = true;

    settings.OOM = {
      SwapUsedLimit = "90%";
      DefaultMemoryPressureDurationSec = "20s";
    };
  };

  systemd.slices."-".sliceConfig = {
    ManagedOOMSwap = "kill";
  };

  flyingcircus.initrd = {
    formatXFS = {
      "/dev/disk/by-partlabel/tmp" = "-L tmp -q -K -d su=4m,sw=1";
    };
    collectQemuData = true;
  };

  networking = {
    domain = "fcio.net";
    extraHosts = lib.optionalString (cfg.hostRgwAddress != null) ''
      # Use this for fast radosgw (S3-compatible) object storage access (port 7480).
      ${cfg.hostRgwAddress} rgw.local
    '';
    hostName = config.fclib.mkPlatform (attrByPath [ "name" ] "default" cfg.enc);
  };

  flyingcircus.systemd.protectedServices = [ "qemu-guest-agent" ];

  services = {
    qemuGuest.enable = true;

    udev.extraRules = ''
      # GRUB boot device should be device-by-alias/root
      SUBSYSTEM=="block", KERNEL=="vda", SYMLINK+="disk/device-by-alias/root"
      SUBSYSTEM=="block", ACTION=="add|change", KERNEL=="vd[a-z]", ATTR{queue/scheduler}="${ioScheduler}", ATTR{queue/rotational}="0"
    '';
  };

  services.journald.extraConfig = ''
    SystemMaxUse=2G
    MaxLevelConsole=notice
    ForwardToWall=no
  '';

  systemd = {
    ctrlAltDelUnit = "poweroff.target";

    timers.serial-console-liveness = {
      description = "Timer for Serial console liveness marker";
      requiredBy = [ "serial-getty@ttyS0.service" ];
      timerConfig = {
        OnBootSec = "10m";
        OnUnitActiveSec = "10m";
      };
    };

    services = {
      serial-console-liveness = {
        description = "Serial console liveness marker";
        serviceConfig.Type = "oneshot";
        script = "echo \"$(date) -- SERIAL CONSOLE IS LIVE --\" > /dev/ttyS0";
      };

      fc-agent.serviceConfig =
        let
          # Must not consume more than 75% of available IOPS.
          # The systemd setting is split between read and write but
          # we only have one IOPS limit for the VM so combined we
          # could get requests that are over the VM limit.
          vdaIopsMax = "/dev/vda ${toString (maxIops - maxIops / 4)}";
        in
        # PL-133877
        if ioScheduler == "none" then
          {
            IOReadIOPSMax = vdaIopsMax;
            IOWriteIOPSMax = vdaIopsMax;
          }
        else
          agentThrottling 20; # 1/5th performance compared to a single user service process

      fc-collect-garbage.serviceConfig =
        let
          # Must not consume more than 12.5% of available IOPS.
          # We don't have a problem with this taking really long.
          vdaIopsMax = "/dev/vda ${toString (maxIops / 8)}";
        in
        # PL-133877
        if ioScheduler == "none" then
          {
            IOReadIOPSMax = vdaIopsMax;
            IOWriteIOPSMax = vdaIopsMax;
          }
        else
          agentThrottling 10; # 1/10th performance compared to a single user service process

      fc-update-channel.serviceConfig =
        let
          # Must not consume more than 12.5% of available IOPS.
          # We don't have a problem with this taking really long.
          vdaIopsMax = "/dev/vda ${toString (maxIops / 8)}";
        in
        # PL-133877
        if ioScheduler == "none" then
          {
            IOReadIOPSMax = vdaIopsMax;
            IOWriteIOPSMax = vdaIopsMax;
          }
        else
          agentThrottling 10; # 1/10th performance compared to a single user service process
    };
  };

  users.users.root = {
    hashedPassword = "*";
    openssh.authorizedKeys.keys = attrValues cfg.static.adminKeys;
  };

  flyingcircus.services.sensu-client.checks = {
    cpu_steal = {
      notification = "CPU has high amount of `%steal` ";
      command = "${pkgs.fc.sensuplugins}/bin/check_cpu_steal " + "--mpstat ${pkgs.sysstat}/bin/mpstat";
      interval = 600;
    };
  };
}
