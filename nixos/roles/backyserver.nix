{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  role = config.flyingcircus.roles.backyserver;
  enc = config.flyingcircus.enc;

  backy = pkgs.backy;

  backyExtract = let
    src = pkgs.fetchFromGitHub {
      owner = "flyingcircusio";
      repo = "backy-extract";
      # 1.1.0
      rev = "5fd4c02e757918e22b634b16ae86927b82eb9f2a";
      sha256 = "1msg4p4h6ksj3vrsshhh5msfwgllai42jczyvd4nvrsqpncg12ik";
    };
    in
      pkgs.callPackage src {};

  restoreSingleFiles = pkgs.callPackage ../../pkgs/restore-single-files {};

  cephPkgs = fclib.ceph.mkPkgs role.cephRelease;
  backyRbdVersioned = {
    BACKY_RBD = "${cephPkgs.ceph-client}/bin/rbd";
  };

  external_header = "/srv/backy.luks";
  mountDirToSystemdUnit = path: builtins.substring 1 (-1) (builtins.replaceStrings ["/"] ["-"] path);
  backyMountDir = "/srv/backy";
  backyMountUnit = "${mountDirToSystemdUnit backyMountDir}.mount";

in
{
  options = {
    flyingcircus.roles.backyserver = {
      enable = lib.mkEnableOption "Backy backup server";

      worker-limit = lib.mkOption {
        description = "Maximum number of parallel backups to run.";
        default = 3;
        type = lib.types.int;
      };

      blockDevice = lib.mkOption {
        type = lib.types.str;
        description = ''
          The *unencrypted* blockdevice to be used as a base for an encrypted Backy volume.
          Can be provided in fstab/ crypttab syntax as well, e.g. `LABEL=`.
          Examples are a partition, mdraid or logical volume.'';
        default = "/dev/vgbackup/backy-crypted";
      };

      externalCryptHeader = lib.mkOption {
        type = lib.types.bool;
        description = ''
          Does the specified `blockdevice` require an external LUKS header?
          This is the case for existing reencrypted devices. Expects a file in ${external_header}.
        '';
        default = false;
      };

      supportsContainers = fclib.mkDisableContainerSupport;


      cephRelease = fclib.ceph.releaseOption // {
        description = "Codename of the Ceph release series used as external backy tooling.";
      };
    };

  };

  config = lib.mkIf role.enable {

    flyingcircus.services.ceph.client = {
      enable = true;
      cephRelease = role.cephRelease;
    };

    flyingcircus.services.consul.enable = true;

    environment.systemPackages = [
      backy
      backyExtract
      restoreSingleFiles
    ];

    # globally set the RBD to be used by backy, in case it is invoked manually by an operator
    environment.variables = backyRbdVersioned;

    environment.etc.crypttab.text = ''
      backy	${role.blockDevice}	/mnt/keys/${config.networking.hostName}.key	discard,nofail,submit-from-crypt-cpus${lib.optionalString role.externalCryptHeader ",header=${external_header}"}
    '';

    fileSystems.${backyMountDir} = {
      device = "/dev/disk/by-label/backy";
      fsType = "xfs";
    };

    services.telegraf.extraConfig.inputs.disk = [
      { mount_points = [ "/srv/backy" ]; }
    ];

    boot = {
      # Extracted to flyingcircus-physical.nix
      # kernel.sysctl."vm.vfs_cache_pressure" = 10;
      kernelModules = [ "mq_deadline" ];
    };

    environment.etc."backy.global.conf".text = ''
      global:
        base-dir: /srv/backy
        worker-limit: ${toString role.worker-limit}
        backup-completed-callback: fc-backy-publish
      schedules:
        default:
          daily: {interval: 1d, keep: 10}
          weekly: {interval: 7d, keep: 4}
          monthly: {interval: 30d, keep: 4}
        frequent:
          hourly: {interval: 1h, keep: 25}
          daily: {interval: 1d, keep: 10}
          weekly: {interval: 7d, keep: 4}
          monthly: {interval: 30d, keep: 4}
        reduced:
          daily: {interval: 1d, keep: 8}
          weekly: {interval: 7d, keep: 3}
          monthly: {interval: 30d, keep: 2}
        longterm:
          daily: {interval: 1d, keep: 30}
          monthly: {interval: 30d, keep: 12}
        frequent+longterm:
          hourly: {interval: 1h, keep: 25}
          daily: {interval: 1d, keep: 30}
          monthly: {interval: 30d, keep: 12}
    '';

    flyingcircus.agent.extraCommands = ''
        timeout 900 fc-backy -r || rc=$?
    '';

    systemd.services.backy = {
        description = "Backy backup server";
        wantedBy = [ "multi-user.target" ];
        path = [ backy pkgs.fc.agent ];
        # prevent accidentally writing into an empty mount directory,
        # as mountpoint is nofail now
        requires = [ backyMountUnit ];
        after = [ backyMountUnit ];

        environment = {
          CEPH_ARGS = "--id ${enc.name}";
        } // backyRbdVersioned;

        serviceConfig = {
          ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
          Restart = "always";
        };

        script = ''
            set -e

            # Delete old logs from pre-journal days.
            rm -f /var/log/backy.log*

            if ! [[ -f /etc/backy.conf ]]; then
              fc-backy
            fi
            exec ${backy}/bin/backy scheduler
        '';

    };

    services.logrotate.extraConfig = ''
        /srv/backy/*/backy.log {
        }
      '';

    flyingcircus.services.sensu-client.checks = {

      backy_sla = {
        notification = "Backy SLA conformance";
        command = "sudo ${backy}/bin/backy check";
      };

    };

    flyingcircus.passwordlessSudoRules = [
      { commands = [ "${backy}/bin/backy check" ];
        groups = [ "sensuclient" ];
      }
    ];

  };
}
