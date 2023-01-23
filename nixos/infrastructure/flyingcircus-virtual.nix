{ config, lib, pkgs, ... }:

with lib;

let
  inherit (config) fclib;
  cfg = config.flyingcircus;
  ioScheduler =  if (cfg.infrastructure.preferNoneSchedulerOnSsd && (cfg.enc.parameters.rbd_pool == "rbd.ssd"))
                 then "none"
                 else "bfq";
  maxIops = attrByPath [ "parameters" "iops" ] 250 cfg.enc;

  # We allow VMs to talk to their KVM host's radosgw proxy to provide them
  # with fast storage access.
  hostRgwServices = fclib.findServices "kvm_host-local-rgw";
  hostmap =
    lib.listToAttrs
      (map (s: lib.nameValuePair (head (lib.splitString "." s.address)) (head s.ips))
      hostRgwServices);

  kvmHost = config.flyingcircus.enc.parameters.kvm_host or "none";
  hostRgwAddress = hostmap."${kvmHost}" or null;

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
      gfxmodeBios = lib.mkForce "text";
    };
  };

  flyingcircus.hostRgwAddress = hostRgwAddress;

  flyingcircus.journalbeat.fields =
    let encParams = [
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
    lib.optionalAttrs
      (cfg.enc ? "parameters")
      (lib.filterAttrs
        (n: v: v != null)
        (lib.listToAttrs
          (map
            (name: lib.nameValuePair name (cfg.enc.parameters."${name}" or null))
            encParams)));

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
    extraHosts = lib.optionalString (hostRgwAddress != null) ''
      # Use this for fast radosgw (S3-compatible) object storage access (port 7480).
      ${hostRgwAddress} rgw.local
    '';
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
        in {
          IOReadIOPSMax = vdaIopsMax;
          IOWriteIOPSMax = vdaIopsMax;
        };

      fc-collect-garbage.serviceConfig =
        let
          # Must not consume more than 12.5% of available IOPS.
          # We don't have a problem with this taking really long.
          vdaIopsMax = "/dev/vda ${toString (maxIops / 8)}";
        in {
          IOReadIOPSMax = vdaIopsMax;
          IOWriteIOPSMax = vdaIopsMax;
        };
    };
  };

  users.users.root = {
    hashedPassword = "*";
    openssh.authorizedKeys.keys =
      attrValues cfg.static.adminKeys;
  };

  flyingcircus.services.sensu-client.checks = {
    cpu_steal = {
      notification = "CPU has high amount of `%steal` ";
      command =
        "${pkgs.fc.sensuplugins}/bin/check_cpu_steal " +
        "--mpstat ${pkgs.sysstat}/bin/mpstat";
      interval = 600;
    };
  };
}
