{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  role = config.flyingcircus.roles.kvm_host;
  enc = config.flyingcircus.enc;

  qemu_ceph_versioned = cephReleaseName: (pkgs.qemu_ceph.override {
     ceph = fclib.ceph.releasePkgs.${cephReleaseName};
     });
  fc-qemu_versioned = cephReleaseName: (pkgs.fc.qemu.override {
     ceph = fclib.ceph.releasePkgs.${cephReleaseName};
     qemu_ceph = qemu_ceph_versioned cephReleaseName;
  });

in
{
  options = {
    flyingcircus.roles.kvm_host = {
      enable = lib.mkEnableOption "Qemu/KVM server";
      supportsContainers = fclib.mkDisableContainerSupport;
      mkfsXfsFlags = lib.mkOption {
        type = with lib.types; nullOr str;
        # XXX: reflink=0 can be removed when 15.09 is out. See #PL-130977
        # XXX: set reflink=0 to make file systems compatible with NixOS 15.09
        default = "-q -f -K -m crc=1,finobt=1,reflink=0 -d su=4m,sw=1";
      };
      package = lib.mkOption {
        type = lib.types.package;
        description = ''
          fc.qemu package for the role to use.

          Can be replaced for development and testing purposes.
        '';
        default = fc-qemu_versioned role.cephRelease;
        defaultText = literalExpression "pkgs.fc.qemu [parameterised with cephRelease]";
      };
      cephRelease = fclib.ceph.releaseOption // {
        description = "Codename of the Ceph release series used by qemu.";
      };
    };
  };

  config = lib.mkIf role.enable {

    flyingcircus.services.ceph.client = {
      enable = true;
      cephRelease = role.cephRelease;
    };

    # toolpath for agent (fc-create-vm)
    flyingcircus.agent.extraSettings.Node.path = lib.makeBinPath [
      fclib.ceph.releasePkgs.${role.cephRelease}
      pkgs.util-linux
      pkgs.e2fsprogs
    ];

    boot = {
      kernelModules = [ "kvm" "kvm_intel" "kvm_amd" ];
    };

    environment.systemPackages = with pkgs; [
      role.package
      (qemu_ceph_versioned role.cephRelease)
      bridge-utils
    ];

    environment.shellAliases = {
      # alias for observing both running VMs as well as the migration logs at once
      fc-vm-migration-watch = "watch '${role.package}/bin/fc-qemu ls; echo; grep migration-status /var/log/fc-qemu.log | tail'";
    };

    environment.etc."qemu/fc-qemu.conf".text = let
      hostname = config.networking.hostName;
      migration_address = fclib.fqdn { vlan = "sto"; domain = "gocept.net"; };
      migration_ctl_address = fclib.fqdn { vlan = "mgm"; domain = "gocept.net"; };
    in ''
        [qemu]
        accelerator = kvm
        ; qemu 4.1 compatibility
        machine-type = pc-i440fx-4.1
        vhost = true
        ; The 127.0.0.1 is important. Turning this to "localhost" confuses Qemu's
        ; VNC ACL because it gets mixed up with ::1.
        vnc = 127.0.0.1:{id}
        timeout-graceful = 120
        migration-address = tcp:${migration_address}:{id}
        migration-ctl-address = ${migration_ctl_address}:0
        max-downtime = 4.0
        ; generation 2 = #23965 upgrade to 2.7 due to security issues
        binary-generation = 2
        vm-max-total-memory = ${toString enc.parameters.kvm_net_memory}
        vm-expected-overhead = 512

        [qemu-throttle-by-pool]
        rbd.hdd = 250
        rbd.ssd = 10000

        [consul]
        access-token = ${enc.parameters.secrets."consul/master_token"}
        event-threads = 10

        [ceph]
        client-id = ${hostname}
        cluster = ceph
        lock_host = ${hostname}
        create-vm = ${pkgs.fc.agent}/bin/fc-create-vm -I {name}
     '' + lib.optionalString (role.mkfsXfsFlags != null) ''
        mkfs-xfs = ${role.mkfsXfsFlags}
     '';

    # This needs to stay as is because the path is kept alive during live
    # migration.
    environment.etc."kvm/kvm-ifup" = {
      text = ''
        #!${pkgs.stdenv.shell}
        # Wire up Qemu tap devices to the bridge of the corresponding VLAN.
        # Interface names are expected to be of the form `t<VLAN><ifnumber>`, for example:
        # tsrv0, tsrv1, tfe0, ...

        INTERFACE="$1"
        VLAN=$(echo $INTERFACE | sed 's/t\([a-zA-Z]\+\)[0-9]\+/\1/')
        BRIDGE="br''${VLAN}"

        ${pkgs.iproute}/bin/ip link set $INTERFACE up
        ${pkgs.iproute}/bin/ip link set mtu $(< /sys/class/net/eth''${VLAN}/mtu) dev $INTERFACE
        ${pkgs.bridge-utils}/bin/brctl addif $BRIDGE $INTERFACE
        '';
      mode = "0744";
    };

    environment.etc."kvm/kvm-ifdown" = {
      text = ''
        #!${pkgs.stdenv.shell}
        INTERFACE="$1"
        VLAN=$(echo $INTERFACE | sed 's/t\([a-zA-Z]\+\)[0-9]\+/\1/')
        BRIDGE="br''${VLAN}"

        ${pkgs.bridge-utils}/bin/brctl delif $BRIDGE $INTERFACE
        ${pkgs.iproute}/bin/ip link set $INTERFACE down
        '';
      mode = "0744";
    };

    flyingcircus.services.consul.enable = true;
    flyingcircus.services.consul.watches = [
      { handler_type = "script";
        args = ["/run/wrappers/bin/sudo" "${role.package}/bin/fc-qemu" "-v" "handle-consul-event"];
        type = "keyprefix";
        prefix = "node/";
      }

      { handler_type = "script";
        args = ["/run/wrappers/bin/sudo" "${role.package}/bin/fc-qemu" "-v" "handle-consul-event"];
        type = "keyprefix";
        prefix = "snapshot/";
      }
    ];

    flyingcircus.passwordlessSudoRules = [
      {
        commands = [
          "${role.package}/bin/fc-qemu -v handle-consul-event"
          "/home/ctheune/fc.qemu/result/bin/fc-qemu -v handle-consul-event"
           ];
        users = [ "consul" ];
      }

      { commands = [ "${role.package}/bin/fc-qemu check" ];
        groups = [ "sensuclient" ];
      }
    ];

    systemd.services.fc-qemu-reattach-taps = {
      description = "Reattach all VM taps if needed.";

      path = [ pkgs.jq pkgs.iproute ];

      script = ''
        for interface in $(ip -j link show |  jq '.[] | .ifname' -r | egrep '^t(srv|fe)'); do
          echo "Ensuring attachment of $interface"
          /etc/kvm/kvm-ifup $interface || true
        done
      '';

      wantedBy = [ "multi-user.target" ];
      bindsTo = [ "brfe-netdev.service" "brsrv-netdev.service" ];
      after = [ "brfe-netdev.service" "brsrv-netdev.service" ];

      serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

    };

    systemd.services.fc-qemu-report-cpus = {
      description = "Report supported Qemu CPU models to the directory.";

      wantedBy = [ "multi-user.target" ];

      script = ''
        ${role.package}/bin/fc-qemu report-supported-cpu-models
      '';

      serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
      };

    };

    systemd.tmpfiles.rules = [
      "d /var/log/vm 0755 root root -"
      "d /etc/qemu/vm 0755 root root -"
    ];

    services.logrotate.extraConfig =
      ''
        /var/log/vm/*.[!q]*log {
            # "create" is important - stops log files of outmigrated VMs to be dropped
            # from the shell glob above.
            create 0644 root root
            copytruncate
            nodelaycompress
            rotate 14
        }

        /var/log/fc-qemu.log {
            # There is no sensitive data in this log and we sometimes miss to extract
            # crash information within two weeks. Keep a longer history so we can
            # actually analyze crashes even much later.
            rotate 90
        }
      '';

    flyingcircus.services.sensu-client.checks = {
      qemu = {
        notification = "Qemu health check";
        command = "sudo ${role.package}/bin/fc-qemu check";
      };
    };

    flyingcircus.agent.maintenance.kvm = {
      enter = "${role.package}/bin/fc-qemu maintenance enter";
    };

    systemd.services.fc-qemu-scrub = {
      description = "Scrub Qemu/KVM VM inventory.";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.fc.agent role.package ];
      serviceConfig = {
        Type = "oneshot";
      };

      script = "fc-qemu-scrub";
    };

    systemd.timers.fc-qemu-scrub = {
      description = "Runs the Qemu/KVM scrub script regularly.";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnUnitActiveSec = "10m";
      };
    };

    boot.kernel.sysctl = {
      # Agressively try to reclaim memory on the local NUMA node if a slub cache runs
      # empty. Note that we still don't allow disk I/O to happen to satisfy kernel
      # memory allocations.
      "vm.zone_reclaim_mode" = "1";

      # Qemu hosts tend to cycle PIDs pretty fast
      "kernel.pid_max" = lib.mkForce "999999";  # mkForce to avoid conflict with ceph role
    };

  };
}
