{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  role = config.flyingcircus.roles.ceph_mon;
  enc = config.flyingcircus.enc;
  mon_port = "6789";

  mons = (sort lessThan (map (service: service.address) (fclib.findServices "ceph_mon-mon")));
  # We do not have service data during bootstrapping.
  first_mon = if mons == [ ] then "" else head (lib.splitString "." (head mons));

  fc-check-ceph-withVersion = pkgs.fc.check-ceph.${role.cephRelease};
in
{
  options = {
    flyingcircus.roles.ceph_mon = {
      enable = lib.mkEnableOption "CEPH Monitor";
      supportsContainers = fclib.mkDisableContainerSupport;

      primary = lib.mkOption {
        default = (first_mon == config.networking.hostName);
        description = "Primary monitors take over additional maintenance tasks.";
        type = lib.types.bool;
      };

      config = lib.mkOption {
        type = lib.types.lines;
        default = (lib.concatMapStringsSep "\n"
          (mon:
            let
              id = head (lib.splitString "." mon.address);
              addr = "${head (filter fclib.isIp4 mon.ips)}:${mon_port}";
            in
            ''
              [mon.${id}]
              host = ${id}
              mon addr = ${addr}
              public addr = ${addr}
            '')
          (fclib.findServices "ceph_mon-mon"));
        description = ''
          Contents of the Ceph config file for MONs.
        '';
      };

      cephRelease = fclib.ceph.releaseOption // {
        description = "Codename of the Ceph release series used for the the mon package.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf role.enable {
      flyingcircus.services.ceph = {
        fc-ceph.settings = let
          monSettings =  {
            release = role.cephRelease;
            path = fclib.ceph.fc-ceph-path fclib.ceph.releasePkgs.${role.cephRelease};
          };
        in {
          # fc-ceph monitor components
          Monitor = monSettings;
          Manager = monSettings;
          # use the same ceph release for KeyManager, as authentication is significantly
          # coordinated by mons
          KeyManager = monSettings;
          };

        server = {
          enable = true;
          cephRelease = role.cephRelease;
        };
      };

      environment.etc."ceph/ceph.conf".text = lib.mkAfter role.config;

      systemd.services.fc-ceph-mon = rec {
        description = "Local Ceph Mon (via fc-ceph)";
        wantedBy = [ "multi-user.target" ];
        # Ceph requires the IPs to be properly attached to interfaces so it
        # knows where to bind to the public and cluster networks.
        wants = [ "network.target" ];
        after = wants;

        restartTriggers = [
          config.environment.etc."ceph/ceph.conf".source
          fclib.ceph.releasePkgs.${role.cephRelease}
        ];

        environment = {
          PYTHONUNBUFFERED = "1";
        };

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
            "${fc-check-ceph-withVersion}/bin/check_ceph"
          ];
          groups = [ "sensuclient" ];
        }
      ];

      flyingcircus.services.sensu-client.checks = with pkgs; {
        ceph = {
          notification = "Ceph cluster is healthy";
          command = "sudo ${fc-check-ceph-withVersion}/bin/check_ceph -v -R 200 -A 300";
          interval = 60;
        };
      };

      environment.systemPackages = [ fc-check-ceph-withVersion ];

      systemd.services.fc-ceph-load-vm-images = {
        description = "Load new VM base images";
        serviceConfig.Type = "oneshot";
        script = "${pkgs.fc.ceph}/bin/fc-ceph maintenance load-vm-images";
        environment = {
          PYTHONUNBUFFERED = "1";
        };
      };

      systemd.services.fc-ceph-purge-old-snapshots = {
        description = "Purge old snapshots";
        serviceConfig.Type = "oneshot";
        script = "${pkgs.fc.ceph}/bin/fc-ceph maintenance purge-old-snapshots";
        environment = {
          PYTHONUNBUFFERED = "1";
        };
      };

      systemd.services.fc-ceph-clean-deleted-vms = {
        description = "Purge old snapshots";
        serviceConfig.Type = "oneshot";
        script = "${pkgs.fc.ceph}/bin/fc-ceph maintenance clean-deleted-vms";
        environment = {
          PYTHONUNBUFFERED = "1";
        };
      };

      systemd.services.fc-ceph-mon-update-client-keys = {
        description = "Update client keys and authorization in the monitor database.";
        serviceConfig.Type = "oneshot";
        script = "${pkgs.fc.ceph}/bin/fc-ceph keys mon-update-client-keys";
        environment = {
          PYTHONUNBUFFERED = "1";
        };
      };

    })
    (lib.mkIf (role.enable && role.cephRelease != "jewel") {
      systemd.services.fc-ceph-mgr = rec {
        description = "Local Ceph MGR (via fc-ceph)";
        wantedBy = [ "multi-user.target" ];
        # Ceph requires the IPs to be properly attached to interfaces so it
        # knows where to bind to the public and cluster networks.
        wants = [ "network.target" ];
        after = wants;

        restartTriggers = [
          config.environment.etc."ceph/ceph.conf".source
          fclib.ceph.releasePkgs.${role.cephRelease}
        ];

        environment = {
          PYTHONUNBUFFERED = "1";
        };

        script = ''
          ${pkgs.fc.ceph}/bin/fc-ceph mgr activate
        '';

        reload = ''
          ${pkgs.fc.ceph}/bin/fc-ceph mgr reactivate
        '';

        # FIXME: dashboard only enabled for luminous, as the Nautilus release fails to build in the sandbox so far.
        # If we ever manage to get it enabled, `ceph config set` needs to be used instead of `ceph config-key`
        preStart = lib.optionalString (role.cephRelease == "luminous") ''
          echo "ensure mgr dashboard binds to localhost only"
          # make _all_ hosts bind the dashboard to localhost (v4) only (default port: 7000)
          ${fclib.ceph.releasePkgs.${role.cephRelease}}/bin/ceph config-key set mgr/dashboard/server_addr 127.0.0.1
          echo "ensure mgr dashboard is enabled"
          # --force is required for bootstrapping, as otherwise ceph complains that not all mgrs support that module in the state of "no mgrs exist"
          ${fclib.ceph.releasePkgs.${role.cephRelease}}/bin/ceph mgr module enable dashboard --force'';

        preStop = ''
          ${pkgs.fc.ceph}/bin/fc-ceph mgr deactivate
        '';

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
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

    })
  ];

}
