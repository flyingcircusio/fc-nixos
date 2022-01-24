{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  role = config.flyingcircus.roles.backyserver;
  enc = config.flyingcircus.enc;

  backy = pkgs.callPackage ../../pkgs/backy.nix { };

  backyExtract = let
    src = pkgs.fetchFromGitHub {
      owner = "flyingcircusio";
      repo = "backy-extract";
      rev = "5fd4c02e757918e22b634b16ae86927b82eb9f2a";
      sha256 = "1msg4p4h6ksj3vrsshhh5msfwgllai42jczyvd4nvrsqpncg12ik";
    };
    in
      pkgs.callPackage src {};

  restoreSingleFiles = pkgs.callPackage ../../pkgs/restore-single-files {};

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

      supportsContainers = fclib.mkDisableContainerSupport;

    };

  };

  config = lib.mkIf role.enable {

    flyingcircus.services.ceph.client.enable = true;
    flyingcircus.services.consul.enable = true;

    environment.systemPackages = [
      backy
      backyExtract
      restoreSingleFiles
    ];

    fileSystems = {
      "/srv/backy" = {
        device = "/dev/disk/by-label/backy";
        fsType = "xfs";
      };
    };

    boot = {
      kernel.sysctl."vm.vfs_cache_pressure" = 10;
      kernelModules = [ "mq_deadline" ];
    };

    environment.etc."backy.global.conf".text = ''
      global:
        base-dir: /srv/backy
        worker-limit: ${toString role.worker-limit}
      schedules:
        default:
          daily: {interval: 1d, keep: 10}
          monthly: {interval: 30d, keep: 4}
          weekly: {interval: 7d, keep: 4}
        frequent:
          daily: {interval: 1d, keep: 10}
          hourly: {interval: 1h, keep: 25}
          monthly: {interval: 30d, keep: 4}
          weekly: {interval: 7d, keep: 4}
        reduced:
          daily: {interval: 1d, keep: 8}
          monthly: {interval: 30d, keep: 2}
          weekly: {interval: 7d, keep: 3}
        longterm:
          daily: {interval: 1d, keep: 30}
          monthly: {interval: 30d, keep: 12}
    '';

    flyingcircus.agent.extraCommands = ''
        timeout 900 fc-backy -r || rc=$?
    '';

    systemd.services.backy = {
        description = "Backy backup server";
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.backy pkgs.fc.agent ];

        environment = {
          CEPH_ARGS = "--id ${enc.name}";
        };

        serviceConfig = {
          ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        };

        # Theory of operation: raising write_expire timeouts means that
        # requests are much more unlikely to get into 'expired' state which effectively
        # means FIFO which means thrashing under high load.
        script = ''
            set -e

            # Delete old logs from pre-journal days.
            rm -f /var/log/backy.log*

            for device in /sys/block/*; do
                if ! [[ -d ''${device} ]]; then
                    continue
                fi

                case ''${device##*/} in
                    sd?)
                        echo "mq-deadline" > "''${device}/queue/scheduler"
                        sleep 0.1
                        echo 50000 > "''${device}/queue/iosched/write_expire"  # default: 5000
                    ;;
                esac
            done

            if ! [[ -f /etc/backy.conf ]]; then
              fc-backy
            fi
            exec ${pkgs.backy}/bin/backy scheduler
        '';

    };

    services.logrotate.extraConfig = ''
        /srv/backy/*/backy.log {
        }
      '';

    flyingcircus.services.sensu-client.checks = {

      backy_sla = {
        notification = "Backy SLA conformance";
        command = "sudo ${pkgs.backy}/bin/backy check";
      };

    };

    flyingcircus.passwordlessSudoRules = [
      { commands = [ "${pkgs.backy}/bin/backy check" ];
        groups = [ "sensuclient" ];
      }
    ];

  };
}
