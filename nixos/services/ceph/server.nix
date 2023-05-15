{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  enc = config.flyingcircus.enc;

  ceph_sudo = pkgs.writeScriptBin "ceph-sudo" ''
    #! ${pkgs.stdenv.shell} -e
    exec /run/wrappers/bin/sudo ${cfg.package}/bin/ceph "$@"
  '';

  cfg = config.flyingcircus.services.ceph.server;

  fc-ceph = pkgs.fc.cephWith cfg.package;

in
{
  options = {
    flyingcircus.services.ceph.server = {
      enable = lib.mkEnableOption "Generic CEPH server configuration";
      cephRelease = lib.mkOption {
        type = fclib.ceph.highestCephReleaseType;
        description = "Ceph release series that the main package belongs to. "
          + "This option behaves special in a way that, if defined multiple times, the latest release name will be chosen."
          + "Explicitly has no default but needs to be defined by roles or manual config.";
      };
      package = lib.mkOption {
        type = lib.types.package;
        description = "Main ceph package to be used on the system and to be put into PATH. "
          + "The package set must belong to the release series defined in the `cephRelease` option. "
          + "Only modify if really necessary, otherwise the default ceph package from the defined series is used.";
        default = fclib.ceph.releasePkgs.${cfg.cephRelease};
      };
      crushroot_to_rbdpool_mapping = lib.mkOption {
        default = {
          default = [ "rbd.hdd" ];
          ssd = [ "rbd.ssd" ];
        };
        type = let t = lib.types; in t.attrsOf (t.listOf t.str);
        description = ''
          Mapping of which rbd pools are operated under which crush root.
          Currently only used by the check_snapshot_restore_fill check.
          Backgound: We operate our rbd.hdd and rbd.ssd pools under different Ceph crush
          roots to map them to disjoint sets of certain disks.'';
      };
    };
  };

  config = lib.mkIf cfg.enable {

    assertions = [
      {
        assertion = cfg.package.codename == cfg.cephRelease;
        message = "The ceph package set for this ceph server service must be of the same release series as defined in `cephRelease`";
      }
    ];

    environment.variables.CEPH_ARGS = fclib.mkPlatformOverride "";

    flyingcircus.services.ceph.client = {
      enable = true;
      # set same ceph package to avoid conflicts
      cephRelease = cfg.cephRelease;
    };

    flyingcircus.agent.maintenance.ceph = {
      enter = "${fc-ceph}/bin/fc-ceph maintenance enter";
      leave = "${fc-ceph}/bin/fc-ceph maintenance leave";
    };

    # We used to create the admin key directory from the ENC. However,
    # this causes the file to become world readable on Ceph servers.

    flyingcircus.activationScripts.ceph-admin-key = ''
      # Only allow root to read/write this file
      umask 066
      echo -e "[client.admin]\nkey = $(${pkgs.jq}/bin/jq -r  '.parameters.secrets."ceph/admin_key"' /etc/nixos/enc.json)" > /etc/ceph/ceph.client.admin.keyring
    '';

    systemd.tmpfiles.rules = [
      "d /srv/ceph 0755"
    ];

    flyingcircus.services.sensu-client.expectedConnections = {
      warning = 20000;
      critical = 25000;
    };

    services.logrotate.extraConfig = ''
      /var/log/ceph/ceph.log
      /var/log/ceph/ceph.audit.log
      /var/log/ceph/ceph-mon.*.log
      /var/log/ceph/ceph-osd.*.log
      {
          rotate 30
          create 0644 root adm
          prerotate
              for dmn in $(cd /run/ceph && ls ceph-*.asok 2>/dev/null); do
                  echo "Flushing log for $dmn"
                  ${cfg.package}/bin/ceph --admin-daemon /run/ceph/''${dmn} log flush || true
              done
          endscript
          postrotate
              for dmn in $(cd /run/ceph && ls ceph-*.asok 2>/dev/null); do
                  echo "Reopening log for $dmn"
                  ${cfg.package}/bin/ceph --admin-daemon /run/ceph/''${dmn} log reopen || true
              done
          endscript
      }
    '';

    services.telegraf.extraConfig.inputs.ceph = [
      { ceph_binary = "${ceph_sudo}/bin/ceph-sudo"; }
    ];

    flyingcircus.passwordlessSudoRules = [
      {
        commands = [ "${cfg.package}/bin/ceph" ];
        users = [ "telegraf" ];
      }
    ];

    environment.systemPackages = with pkgs; [
      fc-ceph
      fc.blockdev

      # tools like radosgw-admin and crushtool are only included in the full ceph package, but are necessary admin tools
      cfg.package
    ];

    systemd.services.fc-blockdev = {
      description = "Tune blockdevice settings.";
      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = true;
      wantedBy = [ "basic.target" ];
      script = ''
        ${pkgs.fc.blockdev}/bin/fc-blockdev -a -v
      '';
      environment = {
        PYTHONUNBUFFERED = "1";
      };
    };

    boot.kernel.sysctl = {
      "fs.aio-max-nr" = "262144";
      "fs.xfs.xfssyncd_centisecs" = "720000";

      "vm.dirty_background_ratio" = "10";
      "vm.dirty_ratio" = "40";
      "vm.max_map_count" = "524288";
      # Extracted to flyingcircus-physical.nix
      # kernel.sysctl."vm.vfs_cache_pressure" = 10;

      # 10G tuning for OSDs
      "vm.min_free_kbytes" = "513690";

      "kernel.pid_max" = "999999";
      "kernel.threads-max" = "999999";

      "net.core.netdev_max_backlog" = "300000";
      "net.core.optmem" = "40960";
      "net.core.rmem_default" = "56623104";
      "net.core.rmem_max" = lib.mkForce "56623104";
      "net.core.somaxconn" = "1024";
      "net.core.wmem_default" = "56623104";
      "net.core.wmem_max" = "56623104";

      "net.ipv4.tcp_fin_timeout" = "10";
      "net.ipv4.tcp_max_syn_backlog" = "30000";
      "net.ipv4.tcp_mem" = "4096 87380 56623104";
      "net.ipv4.tcp_rmem" = "4096 87380 56623104";
      "net.ipv4.tcp_slow_start_after_idle" = "0";
      "net.ipv4.tcp_syncookies" = "0";
      "net.ipv4.tcp_timestamps" = "0";
      "net.ipv4.tcp_wmem" = "4096 87380 56623104";

      "net.ipv4.tcp_tw_recycle" = "1";
      "net.ipv4.tcp_tw_reuse" = "1";

      # Supposedly this doesn't do much good anymore, but in one of my tests
      # (too many, can't prove right now.) this appeared to have been helpful.
      "net.ipv4.tcp_low_latency" = "1";
    };
  };

}
