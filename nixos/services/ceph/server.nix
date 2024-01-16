{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  enc = config.flyingcircus.enc;

  ceph_sudo = pkgs.writeScriptBin "ceph-sudo" ''
    #! ${pkgs.stdenv.shell} -e
    exec /run/wrappers/bin/sudo ${cephPkgs.ceph}/bin/ceph "$@"
  '';

  cfg = config.flyingcircus.services.ceph.server;

  cephPkgs = fclib.ceph.mkPkgs cfg.cephRelease;

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
      crushroot_to_rbdpool_mapping = lib.mkOption {
        default = config.flyingcircus.static.ceph.crushroot_to_rbdpool_mapping;
        type = let t = lib.types; in t.attrsOf (t.listOf t.str);
        description = ''
          Mapping of which rbd pools are operated under which crush root.
          Currently only used by the check_snapshot_restore_fill check.
          Background: We operate our rbd.hdd and rbd.ssd pools under different Ceph crush
          roots to map them to disjoint sets of certain disks.'';
      };
    };
  };

  config = lib.mkIf cfg.enable {

    environment.variables.CEPH_ARGS = fclib.mkPlatformOverride "";

    flyingcircus.services.ceph.client = {
      enable = true;
      # set same ceph package to avoid conflicts
      cephRelease = cfg.cephRelease;
    };

    flyingcircus.agent.maintenance.ceph = {
      enter = "${cephPkgs.fc-ceph}/bin/fc-ceph maintenance enter";
      leave = "${cephPkgs.fc-ceph}/bin/fc-ceph maintenance leave";
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
                  ${cephPkgs.ceph}/bin/ceph --admin-daemon /run/ceph/''${dmn} log flush || true
              done
          endscript
          postrotate
              for dmn in $(cd /run/ceph && ls ceph-*.asok 2>/dev/null); do
                  echo "Reopening log for $dmn"
                  ${cephPkgs.ceph}/bin/ceph --admin-daemon /run/ceph/''${dmn} log reopen || true
              done
          endscript
      }
    '';

    services.telegraf.extraConfig.inputs.ceph = [
      { ceph_binary = "${ceph_sudo}/bin/ceph-sudo"; }
    ];

    flyingcircus.passwordlessSudoRules = [
      {
        commands = [ "${cephPkgs.ceph}/bin/ceph" ];
        users = [ "telegraf" ];
      }
    ];

    environment.systemPackages = with pkgs; [
      cephPkgs.fc-ceph
      fc.blockdev

      # tools like radosgw-admin and crushtool are only included in the full ceph package, but are necessary admin tools
      cephPkgs.ceph
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

      "kernel.pid_max" = "999999";
      "kernel.threads-max" = "999999";

      "net.core.somaxconn" = "1024";
    };
  };
}
