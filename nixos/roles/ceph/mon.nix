{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  role = config.flyingcircus.roles.ceph_mon;
  enc = config.flyingcircus.enc;
  mon_port = "6789";

  mons = (sort lessThan (map (service: service.address) (fclib.findServices "ceph_mon-mon")));
  # We do not have service data during bootstrapping.
  first_mon = if mons == [] then "" else head (lib.splitString "." (head mons));
in
{
  options = {
    flyingcircus.roles.ceph_mon = {
      enable = lib.mkEnableOption "CEPH Monitor";

      primary = lib.mkOption {
        default = (first_mon == config.networking.hostName);
        description = "Primary monitors take over additional maintenance tasks.";
        type = lib.types.bool;
       };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf role.enable {
      flyingcircus.services.ceph.server.enable = true;

      flyingcircus.services.ceph.client.config = lib.mkAfter (let
            mon_addrs = lib.concatMapStringsSep ","
                (mon: "${head (filter fclib.isIp4 mon.ips)}:${mon_port}")
                (fclib.findServices "ceph_mon-mon");
          in ''
        [mon]
        admin socket = /run/ceph/$cluster-$name.asok

        mon addr = ${mon_addrs}
        mon data = /srv/ceph/mon/$cluster-$id
        mon osd allow primary affinity = true
        mon pg warn max per osd = 3000

        osd pool default size = 3
        osd pool default min size = 2
        osd pool default pg num = 64
        osd pool default pgp num = 64

        [mon.${config.networking.hostName}]
        host = ${config.networking.hostName}
        mon addr = ${head fclib.network.sto.v4.addresses}:${mon_port}
        public addr = ${head fclib.network.sto.v4.addresses}:${mon_port}
        cluster addr = ${head fclib.network.stb.v4.addresses}:${mon_port}
        '');

      systemd.services.fc-ceph-mon = rec {
        description = "Start/stop local Ceph mon (via fc-ceph)";
        wantedBy = [ "multi-user.target" ];
        # Ceph requires the IPs to be properly attached to interfaces so it
        # knows where to bind to the public and cluster networks.
        wants = [ "network.target" ];
        after = wants;

        environment = {
          PYTHONUNBUFFERED = "1";
        };

        restartIfChanged = false;

        reloadIfChanged = true;
        restartTriggers = [
          config.environment.etc."ceph/ceph.conf".source
          pkgs.ceph
        ];

        script = ''
            ${pkgs.fc.ceph}/bin/fc-ceph mon activate
        '';

        reload = ''
            ${pkgs.fc.ceph}/bin/fc-ceph mon reactivate
        '';

        preStop = ''
           ${pkgs.fc.ceph}/bin/fc-ceph mon deactivate
        '';

        serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
        };
      };


      flyingcircus.passwordlessSudoRules = [
        {
          commands = with pkgs; [
            "${pkgs.fc.check-ceph}/bin/check_ceph"
          ];
          groups = [ "sensuclient" ];
        }
      ];

      flyingcircus.services.sensu-client.checks = with pkgs; {
        ceph = {
          notification = "Ceph cluster is healthy";
          command = "sudo ${pkgs.fc.check-ceph}/bin/check_ceph -v -R 200 -A 300";
          interval = 60;
        };
      };

      environment.systemPackages = [ pkgs.fc.check-ceph ];

      systemd.services.fc-ceph-load-vm-images = {
        description = "Load new VM base images";
        serviceConfig.Type = "oneshot";
        script = "${pkgs.fc.ceph}/bin/fc-ceph maintenance load-vm-images";
      };

      systemd.services.fc-ceph-purge-old-snapshots = {
        description = "Purge old snapshots";
        serviceConfig.Type = "oneshot";
        script = "${pkgs.fc.ceph}/bin/fc-ceph maintenance purge-old-snapshots";
      }; 

      systemd.services.fc-ceph-clean-deleted-vms = {
        description = "Purge old snapshots";
        serviceConfig.Type = "oneshot";
        script = "${pkgs.fc.ceph}/bin/fc-ceph maintenance clean-deleted-vms";
      };

      systemd.services.fc-ceph-mon-update-client-keys = {
        description = "Update client keys and authorization in the monitor database.";
        serviceConfig.Type = "oneshot";
        script = "${pkgs.fc.ceph}/bin/fc-ceph keys mon-update-client-keys";
      };

    })
    (lib.mkIf (role.enable && role.primary) {

      systemd.timers.fc-ceph-load-vm-images = {
        description = "Timer for loading new VM base images";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "10m";
          OnUnitActiveSec = "10m";
        };
      };

      systemd.timers.fc-ceph-purge-old-snapshots = {
        description = "Timer for cleaning old snapshots";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1h";
          OnUnitActiveSec = "3h";
        };
      };

      systemd.timers.fc-ceph-clean-deleted-vms = {
        description = "Timer for cleaning deleted VM disks";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1h";
          OnUnitActiveSec = "3h";
        };
      };

      systemd.timers.fc-ceph-mon-update-client-keys = {
        description = "Timer for updating client keys and authorization in the monitor database.";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5m";
          OnUnitActiveSec = "10m";
        };
      };

    })];

}
