{
  config,
  lib,
  pkgs,
  ...
}:

with builtins;

let
  inherit (config.flyingcircus) location;
  fclib = config.fclib;
  cfg = config.flyingcircus.roles.kvm_host;
  enc = config.flyingcircus.enc;

  cephPkgs = fclib.ceph.mkPkgs cfg.cephRelease;

  fcQemuConfFormat = pkgs.formats.ini { };

  # virtual ipv4 gateway address selected by 254-169=85, with each
  # octet +85 mod 256 the preceding octet
  # XXX duplicated in fc.qemu
  virtualGatewayV4 = "169.254.83.168";
  virtualGatewayV6 = "fe80::1";

  vrfInterfaces = lib.filterAttrs (_: v: v.linktype == "routed") fclib.network;
  vrfV6Resolvers = iface: map (net: "${net.network}1") iface.v6.networkAttrs;

  ubuntuUpdateScript = pkgs.writeShellApplication {
    name = "fc-update-ubuntu";
    runtimeInputs = with pkgs; [ wget ];
    text = (lib.readFile ./update-ubuntu.sh);
  };

  noopScript = {
    text = ''
      #!${pkgs.stdenv.shell}
      : # BBB noop
    '';
    mode = "0744";
  };

  # qemu+nautilus is pinned to an old fc.qemu version which expects
  # guest tap interface setup to be performed by fc-nixos
  noopScriptWithNautilusFallback =
    content: if cfg.cephRelease == "nautilus" then content else noopScript;

in
{
  options = {
    flyingcircus.roles.kvm_host = {
      enable = lib.mkEnableOption "Qemu/KVM server";
      enableS3Proxy = lib.mkOption {
        default = true;
        example = false;
        description = "Whether to enable the local S3 proxy.";
        type = lib.types.bool;
      };

      supportsContainers = fclib.mkDisableDevhostSupport;
      mkfsXfsFlags = lib.mkOption {
        type = with lib.types; nullOr str;
        description = ''
          Note that this should only enable a minimal set of features and that
          each VM later enables the features it supports at boot time.
          (See flyingcircus.initrd.formatXFS/upgradeXFS for more info.)
        '';
        default = "-q -f -K -m crc=1,finobt=1 -i nrext64=0,exchange=0 -d su=4m,sw=1 -n parent=0";
      };
      migrationBandwidth = lib.mkOption {
        type = lib.types.int;
        # 0.8 * 10 Gbit/s in bytes/s
        # int(0.8 * 10 * 10**9 / 8)
        default = 1000000000;
      };
      package = lib.mkOption {
        type = lib.types.package;
        description = ''
          fc.qemu package for the role to use.

          Can be replaced for development and testing purposes.
        '';
        default = cephPkgs.fc-qemu;
        defaultText = lib.literalMD "`pkgs.fc.qemu` *[parameterised with cephRelease]*";
      };
      cephRelease = fclib.ceph.releaseOption // {
        description = "Codename of the Ceph release series used by qemu.";
      };

      network = lib.mkOption {
        type = with lib.types; attrs; # an attrset from fclib.network.<xy>
        default = fclib.network.sto;
        defaultText = "The `sto` network";
        description = "Network to use for migration";
      };

      routedResolverV4 = lib.mkOption {
        type = lib.types.str;
        default = head config.flyingcircus.static.nameservers."${location}";
        defaultText = "The platfrom default IPv4 resolver for this location";
        description = "Routing destination for DNS queries received on the IPv4 virtual gateway address";
      };
      routedResolverV6 = lib.mkOption {
        type = lib.types.str;
        default = head config.flyingcircus.static.nameservers6."${location}";
        defaultText = "The platform default IPv6 resolver for this location";
        description = "Routing destination for DNS queries received on the IPv6 virtual resolver address(es)";
      };

      maintenanceEvacuationTimeout = lib.mkOption {
        type = lib.types.ints.positive;
        # in dev, we deliberately provide insufficient time to test the postpone and retry paths
        default = if (location == "dev") then 60 else 300;
        defaultText = "60s for dev, everywhere else 300s";
        description = ''
          Evacuation timeout in seconds for the maintenance enter guard.
                    If VMs are remaining after this time, the maintenance fails temporarily.'';
      };

      settings = lib.mkOption {
        type = lib.types.submodule {
          freeformType = fcQemuConfFormat.type;
        };
        description = ''
          fc-qemu configuration as a structured attrset.
          Populated with sensible default platform values, but certain settings
          may be fine-grained overriden here, i.e. for tests.
        '';
      };

    };
  };

  config = lib.mkIf cfg.enable {

    # Do not enable the watchdog for KVM hosts globally as we dealt with
    # way too many times.
    flyingcircus.ipmi.watchdogTimeout = fclib.mkPlatform 0;

    flyingcircus.services.ceph.client = {
      enable = true;
      cephRelease = cfg.cephRelease;
    };

    # toolpath for agent (fc-create-vm)
    flyingcircus.agent.extraSettings.Node.path = lib.makeBinPath [
      cephPkgs.ceph-client
      pkgs.util-linux
      pkgs.e2fsprogs
    ];

    boot = {
      kernelModules = [
        "kvm"
        "kvm_intel"
        "kvm_amd"
      ];
    };

    environment.systemPackages = with pkgs; [
      cfg.package
      cephPkgs.qemu
      bridge-utils
      ubuntuUpdateScript
    ];

    # Qemu migration coordination uses random ports at the moment, so we
    # trust this completely at the moment.
    networking.firewall.trustedInterfaces = [ cfg.network.interface ];

    environment.shellAliases = {
      # alias for observing both running VMs as well as the migration logs at once
      fc-vm-migration-watch = "watch '${cfg.package}/bin/fc-qemu ls; echo; grep migration-status /var/log/fc-qemu.log | tail'";
    };

    # iproute2 configuration required by fc-qemu
    environment.etc."iproute2/rt_protos.d/fc-qemu.conf".source =
      "${cfg.package}/share/iproute2/rt_protos";

    flyingcircus.roles.kvm_host.settings =
      let
        hostname = config.networking.hostName;
        migration_address = fclib.fqdn {
          vlan = cfg.network.vlan;
          domain = "gocept.net";
        };
        migration_ctl_address = fclib.fqdn {
          vlan = cfg.network.vlan;
          domain = "gocept.net";
        };
      in
      {
        qemu = {
          accelerator = "kvm";
          machine-type = "pc-i440fx-6.0";
          vhost = true;
          # The 127.0.0.1 is important. Turning this to "localhost" confuses
          # Qemu's VNC ACL because it gets mixed up with ::1.
          vnc = "127.0.0.1:{id}";
          timeout-graceful = 120;
          maintenance-evacuation-timeout = cfg.maintenanceEvacuationTimeout;
          migration-address = "tcp:${migration_address}:{id}";
          migration-ctl-address = "${migration_ctl_address}:0";
          migration-bandwidth = cfg.migrationBandwidth;
          max-downtime = "4.0";
          binary-generation = 3;
          vm-max-total-memory = enc.parameters.kvm_net_memory;
          vm-expected-overhead = 512;
        };

        "block-throttle-rbd.hdd" = {
          iops = 250;
          # 250 mib/s
          bps = 262144000;
          burst-factor = 10;
        };

        "block-throttle-rbd.ssd" = {
          iops = 10000;
          # 500 mib/s
          bps = 524288000;
          burst-factor = 2;
        };

        network = rec {
          underlay_loopback = fclib.underlay.loopback or null;

          # BBB PL-135610 - Need to be kept to allow bi-directional migrations
          # with older fc-nixos incarnations.
          tap-ifup-bridged = "/etc/kvm/kvm-ifup";
          tap-ifdown-bridged = "/etc/kvm/kvm-ifdown";
          tap-ifup-routed = "/etc/kvm/kvm-ifup-vrf";
          tap-ifdown-routed = "/etc/kvm/kvm-ifdown-vrf";
          tap-ifup-dynamic = "/etc/kvm/kvm-ifup-dynamic";
          tap-ifdown-dynamic = "/etc/kvm/kvm-ifdown-dynamic";
          # legacy, also BBB
          tap-ifup-bridge = tap-ifup-bridged;
          tap-ifdown-bridge = tap-ifdown-bridged;
          tap-ifup-vrf = tap-ifup-routed;
          tap-ifdown-vrf = tap-ifdown-routed;
        };

        consul = {
          access-token = enc.parameters.secrets."consul/master_token";
          event-threads = 10;
        };

        ceph = {
          client-id = hostname;
          cluster = "ceph";
          lock_host = hostname;
          create-vm = "${pkgs.fc.agent}/bin/fc-create-vm -I {name}";
        }
        // lib.optionalAttrs (cfg.mkfsXfsFlags != null) {
          mkfs-xfs = cfg.mkfsXfsFlags;
        };
      };

    environment.etc."qemu/fc-qemu.conf".source = fcQemuConfFormat.generate "fc-qemu.conf" cfg.settings;

    # BBB PL-135610 - Need to be kept to allow bi-directional migrations
    # with older fc-nixos incarnations.
    environment.etc."kvm/kvm-ifup" = noopScriptWithNautilusFallback {
      text = ''
        #!${pkgs.stdenv.shell}
        # Wire up Qemu tap devices to the bridge of the corresponding VLAN.
        # Interface names are expected to be of the form `t<VLAN><ifnumber>`, for example:
        # tsrv0, tsrv1, tfe0, ...
        set -e

        INTERFACE="$1"
        VLAN=$(echo $INTERFACE | ${pkgs.gnused}/bin/sed 's/t\([a-zA-Z]\+\)[0-9]\+/\1/')
        BRIDGE="br''${VLAN}"

        ${pkgs.iproute2}/bin/ip link set "$INTERFACE" up
        ${pkgs.iproute2}/bin/ip link set mtu $(< /sys/class/net/br''${VLAN}/mtu) dev "$INTERFACE"
        ${pkgs.iproute2}/bin/ip link set "$INTERFACE" master "$BRIDGE"
      '';
      mode = "0744";
    };
    environment.etc."kvm/kvm-ifdown" = noopScriptWithNautilusFallback {
      text = ''
        #!${pkgs.stdenv.shell}
        INTERFACE="$1"
        VLAN=$(echo $INTERFACE | ${pkgs.gnused}/bin/sed 's/t\([a-zA-Z]\+\)[0-9]\+/\1/')
        BRIDGE="br''${VLAN}"

        ${pkgs.iproute2}/bin/ip link set "$INTERFACE" nomaster
        ${pkgs.iproute2}/bin/ip link set "$INTERFACE" down
        ${pkgs.iproute2}/bin/ip link delete "$INTERFACE"
      '';
      mode = "0744";
    };
    environment.etc."kvm/kvm-ifup-vrf" = noopScriptWithNautilusFallback {
      text = ''
        #!${pkgs.stdenv.shell}
        INTERFACE="$1"
        VLAN=$(echo $INTERFACE | sed 's/t\([a-zA-Z]\+\)[0-9]\+/\1/')
        VRF="vrf''${VLAN}"

        ${pkgs.iproute2}/bin/ip link set $INTERFACE master $VRF

        # add addresses idempotently
        ${pkgs.iproute2}/bin/ip address replace ${virtualGatewayV4}/16 dev $INTERFACE
        ${pkgs.iproute2}/bin/ip address replace ${virtualGatewayV6}/64 dev $INTERFACE

        ${pkgs.iproute2}/bin/ip link set $INTERFACE up
      '';
      mode = "0744";
    };
    environment.etc."kvm/kvm-ifdown-vrf" = noopScriptWithNautilusFallback {
      text = ''
        #!${pkgs.stdenv.shell}
        INTERFACE="$1"

        ${pkgs.iproute2}/bin/ip link set "$INTERFACE" down
        ${pkgs.iproute2}/bin/ip address flush dev "$INTERFACE"
        ${pkgs.iproute2}/bin/ip link set "$INTERFACE" nomaster
        ${pkgs.iproute2}/bin/ip link delete "$INTERFACE"
      '';
      mode = "0744";
    };
    environment.etc."kvm/kvm-ifup-dynamic" = noopScript;
    environment.etc."kvm/kvm-ifdown-dynamic" = noopScript;

    flyingcircus.services.consul.enable = true;
    flyingcircus.services.consul.watches = [
      {
        handler_type = "script";
        args = [
          "/run/wrappers/bin/sudo"
          "${cfg.package}/bin/fc-qemu"
          "-v"
          "handle-consul-event"
        ];
        type = "keyprefix";
        prefix = "node/";
      }

      {
        handler_type = "script";
        args = [
          "/run/wrappers/bin/sudo"
          "${cfg.package}/bin/fc-qemu"
          "-v"
          "handle-consul-event"
        ];
        type = "keyprefix";
        prefix = "snapshot/";
      }
    ];

    flyingcircus.passwordlessSudoRules = [
      {
        commands = [
          "${cfg.package}/bin/fc-qemu -v handle-consul-event"
        ];
        users = [ "consul" ];
      }

      {
        commands = [ "${cfg.package}/bin/fc-qemu check" ];
        groups = [ "sensuclient" ];
      }
    ]
    ++ (lib.optionals (vrfInterfaces != { }) [
      {
        commands = [ "${pkgs.fc.check-kvm-vrf-integrity}/bin/check_kvm_vrf_integrity" ];
        groups = [ "sensuclient" ];
        runAs = ":frrvty";
      }
    ]);

    systemd.services.fc-qemu-reattach-taps = {
      # XXX pull into fc.qemu networking as a direct helper script?
      description = "Reattach all VM taps if needed.";

      path = [
        pkgs.jq
        pkgs.iproute2
      ];

      script = ''
        for interface in $(ip -j link show |  jq '.[] | .ifname' -r | egrep '^t(srv|fe)'); do
          echo "Ensuring attachment of $interface"
          /etc/kvm/kvm-ifup $interface || true
        done
      '';

      wantedBy = [ "multi-user.target" ];
      bindsTo = [
        "brfe-netdev.service"
        "brsrv-netdev.service"
      ];
      after = [
        "brfe-netdev.service"
        "brsrv-netdev.service"
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

    };

    systemd.services.fc-qemu-reattach-vrf-taps = lib.mkIf (fclib.network ? pub) {
      # XXX pull into fc.qemu networking as a direct helper script?
      description = "Reattach all VM taps to VRF devices if needed.";

      path = [
        pkgs.jq
        pkgs.iproute2
      ];

      script = ''
        for interface in $(ip -j link show |  jq '.[] | .ifname' -r | egrep '^tpub'); do
          echo "Ensuring attachment of $interface"
          /etc/kvm/kvm-ifup-vrf $interface || true
        done
      '';

      wantedBy = [ "multi-user.target" ];
      bindsTo = [
        "vrfpub-netdev.service"
      ];
      after = [
        "vrfpub-netdev.service"
      ];

      # trigger a scrub when the vrf netdev changes to ensure that the
      # host routes for the guest interfaces are also set up properly.
      wants = [ "fc-qemu-scrub.service" ];
      before = [ "fc-qemu-scrub.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    systemd.services.fc-qemu-clean-logs =
      let
        fcQemuCleanLogScript = (
          pkgs.writers.writePython3Bin "fc-qemu-clean-logs" { } (builtins.readFile ./clean-logs.py)
        );
      in
      {
        description = "Clean orphaned fc.qemu logs.";

        path = [
          pkgs.python3
          pkgs.lsof
        ];

        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${fcQemuCleanLogScript}/bin/fc-qemu-clean-logs";
        };
      };

    systemd.timers.fc-qemu-clean-logs = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    systemd.services.fc-qemu-report-cpus = {
      description = "Report supported Qemu CPU models to the directory.";

      wantedBy = [ "multi-user.target" ];

      script = ''
        ${cfg.package}/bin/fc-qemu report-supported-cpu-models
      '';

      serviceConfig = {
        Type = "simple";
        RemainAfterExit = true;
      };

    };

    systemd.tmpfiles.rules = [
      "d /var/log/vm 0755 root root -"
      "d /etc/qemu/vm 0755 root root -"
    ];

    services.logrotate.settings = {
      vms = {
        files = [ "/var/log/vm/*.[!q]*log" ];
        # "create" is important - stops log files of outmigrated VMs to be dropped
        # from the shell glob above.
        create = "0644 root root";
        copytruncate = true;
        nodelaycompress = true;
        rotate = 14;
      };

      fc-qemu = {
        files = [ "/var/log/fc-qemu.log" ];
        # There is no sensitive data in this log and we sometimes miss to extract
        # crash information within two weeks. Keep a longer history so we can
        # actually analyze crashes even much later.
        rotate = 90;
      };
    };

    flyingcircus.services.sensu-client = {
      checks = {
        qemu = {
          notification = "Qemu health check";
          command = "sudo ${cfg.package}/bin/fc-qemu check";
        };
      }
      // (lib.optionalAttrs (vrfInterfaces != { }) {
        kvm_vrf_integrity = {
          notification = "VRF routing does not match kernel network state";
          interval = 300;
          command =
            let
              tables = lib.concatMapStringsSep " " (i: toString i.vrfTable) (attrValues vrfInterfaces);
            in
            "sudo -g frrvty ${pkgs.fc.check-kvm-vrf-integrity}/bin/check_kvm_vrf_integrity ${tables}";
        };
      });

      # each qemu process connects directly to multiple OSD's in the
      # ceph cluster for at least 3-4 volumes. let's
      expectedConnections =
        let
          vms = 250;
          disks = 4;
          conn_per_disk = 50;
        in
        {
          warning = vms * disks * conn_per_disk;
          critical = 2 * vms * disks * conn_per_disk;
        };
    };

    flyingcircus.agent = {
      maintenancePreparationSeconds = 1800;
      maintenanceRequestRunnableFor = 3600;
      maintenance.kvm = {
        enter = "${cfg.package}/bin/fc-qemu maintenance enter";
        leave = "${cfg.package}/bin/fc-qemu maintenance leave";
      };
    };

    systemd.services.fc-qemu-scrub = {
      description = "Scrub Qemu/KVM VM inventory.";
      path = [
        pkgs.fc.agent
        cfg.package
      ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = 600; # PL-132323
      };

      script = "fc-qemu-scrub";
    };

    systemd.timers.fc-qemu-scrub = {
      description = "Runs the Qemu/KVM scrub script regularly.";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10m";
        OnUnitActiveSec = "60m";
      };
    };

    boot.kernel.sysctl = {
      # Agressively try to reclaim memory on the local NUMA node if a slub cache runs
      # empty. Note that we still don't allow disk I/O to happen to satisfy kernel
      # memory allocations.
      "vm.zone_reclaim_mode" = "1";

      # Qemu hosts tend to cycle PIDs pretty fast
      "kernel.pid_max" = lib.mkForce "999999"; # mkForce to avoid conflict with ceph role
    }
    // (lib.optionalAttrs (vrfInterfaces != { }) {
      # When we have guests which are attached to layer 3 routed VRFs,
      # we need to enable forwarding for traffic from the guest tap
      # interfaces and the bridge interface for the associated
      # L3VNI.
      #
      # For IPv4 this is easy, as the kernel provides per-interface
      # sysctls which control whether packets received on specific
      # interfaces should be forwarded or not.
      #
      # Under IPv6 however, the per-interface sysctls named
      # "forwarding" don't actually have any control over whether
      # packets received on specific interfaces are forwarded or
      # not. Instead, there is a single *global* sysctl which controls
      # forwarding for *all* interfaces, and the administrator is
      # expected to use a firewall to enforce forwarding policy.
      #
      # In the interests of keeping IPv4 and IPv6 configuration
      # reasonably symmetric, we'll turn on global forwarding and set
      # a firewall for both protocols here.
      "net.ipv4.conf.all.forwarding" = fclib.mkOverridePlatformModule 1;
      "net.ipv4.conf.default.forwarding" = fclib.mkOverridePlatformModule 1;
      "net.ipv6.conf.all.forwarding" = fclib.mkOverridePlatformModule 1;
      "net.ipv6.conf.default.forwarding" = fclib.mkOverridePlatformModule 1;
    });

    # Run a proxy to give VMs running on this host fast access to radosgw.

    flyingcircus.services.haproxy = lib.mkIf cfg.enableS3Proxy {
      enable = true;
      enableStructuredConfig = true;

      frontend = {
        http-in = {
          binds = [ "${head fclib.network.srv.v4.addresses}:7480" ];
          default_backend = "s3";
        };
      };

      backend = {
        s3 = {
          servers = map (
            service:
            let
              name = head (lib.splitString "." service.address);
              address = head (filter fclib.isIp4 service.ips);
            in
            "s3-${name} ${address}:7480 check inter 10s rise 2 fall 1 maxconn 40"
          ) (fclib.findServices "ceph_rgw-internal-server");
          extraConfig = ''
            option httpchk GET /rgw-monitoring/probe
          '';
        };
      };
    };

    networking.firewall.extraCommands =
      let
        srvDevice = config.fclib.network.srv.interface;
      in
      ''
        # Accept traffic to the radosgw service
        ${fclib.iptables "127.0.0.1"} -A nixos-fw -p tcp --dport 7480 -i ${srvDevice} -j nixos-fw-accept
      ''
      + (lib.optionalString (vrfInterfaces != { }) ''
        # Set up KVM server forwarding firewall
        ip46tables -N fc-kvm-forward || true
        ip46tables -A FORWARD -j fc-kvm-forward

        # Allow traffic between the VM pub interfaces and the bridge
        # for the pub VNI. This internally traverses "through" the
        # VRF interface, so this needs to be included in the firewall
        # here as well.
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: net: ''
            ip46tables -A fc-kvm-forward -i t${name}+ -o ${net.vrfInterface} -j ACCEPT
            ip46tables -A fc-kvm-forward -i ${net.vrfInterface} -o t${name}+ -j ACCEPT
            ip46tables -A fc-kvm-forward -i ${net.bridgedLink} -o ${net.vrfInterface} -j ACCEPT
            ip46tables -A fc-kvm-forward -i ${net.vrfInterface} -o ${net.bridgedLink} -j ACCEPT
          '') vrfInterfaces
        )}

        # Block all further forwarding traffic
        ip46tables -A fc-kvm-forward -j nixos-fw-refuse
      '');

    networking.firewall.extraStopCommands = lib.optionalString (fclib.network ? pub) ''
      ip46tables -D FORWARD -j fc-kvm-forward || true
      ip46tables -F fc-kvm-forward 2>/dev/null || true
      ip46tables -X fc-kvm-forward 2>/dev/null || true
    '';

    networking.nat.extraCommands = lib.optionalString (vrfInterfaces != { }) ''
      # Use destination NAT to allow guests to use the virtual
      # gateway address as their DNS resolver, and forward queries
      # to the location-wide resolver
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: _: ''
          iptables -t nat -A nixos-nat-pre -i t${name}+ -d ${virtualGatewayV4} -p udp --dport 53 -j DNAT --to-destination ${cfg.routedResolverV4}
          iptables -t nat -A nixos-nat-pre -i t${name}+ -d ${virtualGatewayV4} -p tcp --dport 53 -j DNAT --to-destination ${cfg.routedResolverV4}
        '') vrfInterfaces
      )}
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: iface:
          lib.concatStringsSep "\n" (
            map (gw: ''
              ip6tables -t nat -A nixos-nat-pre -i t${name}+ -d ${gw} -p udp --dport 53 -j DNAT --to-destination ${cfg.routedResolverV6}
              ip6tables -t nat -A nixos-nat-pre -i t${name}+ -d ${gw} -p tcp --dport 53 -j DNAT --to-destination ${cfg.routedResolverV6}
            '') (vrfV6Resolvers iface)
          )
        ) vrfInterfaces
      )}
    '';

  };
}
