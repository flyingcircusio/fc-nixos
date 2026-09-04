{
  config,
  lib,
  pkgs,
  ...
}:

with builtins;

let
  fclib = config.fclib;
  role = config.flyingcircus.roles.ceph_mon;
  enc = config.flyingcircus.enc;
  inherit (fclib.ceph) normaliseCephOptionAttrs normaliseCephOptionSection;

  mons = (sort lessThan (map (service: service.address) (fclib.findServices "ceph_mon-mon")));
  # We do not have service data during bootstrapping.
  first_mon = if mons == [ ] then "" else head (lib.splitString "." (head mons));

  cephPkgs = fclib.ceph.mkPkgs role.cephRelease;

  # default definitions for the mgr.* options:
  mgrEnabledModules = {
    pacific = [
      # always_on_modules for reference:
      # balancer
      # crash
      # devicehealth
      # orchestrator
      # pg_autoscaler
      # progress
      # rbd_support
      # status
      # telemetry
      # volumes

      "iostat"
    ];
  };
  mgrDisabledModules = {
    pacific = [
      "restful"
    ];
  };
  defaultMonSettings = {
    # A value < 1 would generate health warnings despite the scrub deadlines still being
    # below their max limit
    monWarnPgNotScrubbedRatio = 1;
    monWarnPgNotDeepScrubbedRatio = 1;
    monOsdNearfullRatio = 0.85;
    monOsdFullRatio = 0.95;
    # belongs in the [mon] section for historical reasons
    mgrInitialModules = lib.concatStringsSep " " mgrEnabledModules.${role.cephRelease};
  };
  perMonSettings =
    mon:
    let
      id = head (lib.splitString "." mon.address);
      # we have always been using the default mon ports, so there is no need
      # to explicitly specify a port
      addr = toString (head (filter fclib.isIp4 mon.ips));
    in
    {
      "mon.${id}" = {
        host = id;
        publicAddr = addr;
      };
    };
  defaultMgrSettings = {
    "mgr/pg_autoscaler/log_level" = "warning";
  };
in
{
  options = {
    flyingcircus.roles.ceph_mon = {
      enable = lib.mkEnableOption "CEPH Monitor";
      supportsContainers = fclib.mkDisableDevhostSupport;

      primary = lib.mkOption {
        defaultText = "false";
        default = (first_mon == config.networking.hostName);
        description = "Primary monitors take over additional maintenance tasks.";
        type = lib.types.bool;
      };

      # XXX: only covers the [mon] section, we currently do not specify extraSettings
      # for [mgr] in favour of doing that with a full settings revamp PL-135312
      extraSettings = lib.mkOption {
        type =
          with lib.types;
          attrsOf (oneOf [
            str
            int
            float
            bool
          ]);
        default = { }; # defaults are provided in the config section with a lower priority
        description = ''
          mon config of the Ceph config file.
          Can override existing default setting values. Configuration keys like `mon osd full ratio`''
        + ''
          can alternatively be written in camelCase as `monOsdFullRatio`.
        '';
      };

      cephRelease = fclib.ceph.releaseOption // {
        description = "Codename of the Ceph release series used for the the mon package.";
      };

      mgr = {
        enabledModules = lib.mkOption {
          type = with lib.types; listOf str;
          default = mgrEnabledModules."${role.cephRelease}";
          description =
            "Modules to be explicitly activated via this config,"
            + " always_on modules do not need to be listed here.";
        };
        disabledModules = lib.mkOption {
          type = with lib.types; listOf str;
          default = mgrDisabledModules."${role.cephRelease}";
          description = ''
            Modules that are ensured to be disabled at each mgr start. All other
            modules might be imperatively enabled in the cluster and stay enabled.
            Note that `always_on` modules cannot be disabled so far
          '';
        };
        sendTelemetry = lib.mkOption {
          type = lib.types.bool;
          # If we want to control telemetry at more places, this could become a
          # top-level platform option
          default = true;
          description = ''
            Whether to report telemetry to telemetry.ceph.com or not.
            We do not distinguish between the different ceph telemetry *channels*
            and either send all telemetry, including the `ident` channel, or none
            at all.
            If sending telemetry, the reported cluster description is
            <FCIO Cluster #sha512_of_location/rg>
          '';
        };
      };
    };
  };

  config = lib.mkMerge [

    (lib.mkIf role.enable (
      let
        checkSnapshotCmd = "fc-ceph check snapshot-restore ${configtoml}";
        checkClusterCmd = "fc-ceph check cluster -v -R 200 -A 300";

        # check config generated directly from our platform settings
        configtoml = (pkgs.formats.toml { }).generate "config.toml" {
          thresholds = {
            # use canonical, non-camelCase form of ceph settings
            nearfull = config.flyingcircus.services.ceph.allMergedSettings.mon."mon_osd_nearfull_ratio";
            full = config.flyingcircus.services.ceph.allMergedSettings.mon."mon_osd_full_ratio";
          };
          ceph_roots = config.flyingcircus.services.ceph.server.crushroot_to_rbdpool_mapping;
        };
      in
      {
        flyingcircus.passwordlessSudoPackages = [
          {
            commands = [
              "bin/${checkClusterCmd}"
              "bin/${checkSnapshotCmd}"
            ];
            package = cephPkgs.fc-ceph;
            groups = [ "sensuclient" ];
          }
          {
            commands = [
              "bin/rbd trash ls"
            ];
            package = cephPkgs.ceph;
            groups = [ "sensuclient" ];
          }
        ];

        flyingcircus.services.sensu-client.checks = {
          ceph_snapshot_restore_fill = {
            notification =
              "The Ceph cluster might not have enough space for restoring "
              + "the largest RBD snapshot. (does not consider sparse allocation)";
            command = "sudo ${cephPkgs.fc-ceph}/bin/${checkSnapshotCmd}";
            interval = 600;
          };
          ceph = {
            notification = "Ceph cluster is unhealthy";
            command = "sudo ${cephPkgs.fc-ceph}/bin/${checkClusterCmd}";
            interval = 60;
          };
          rbd_trash = {
            notification = "Unexpected rbd images found in trash.";
            command = ''
              if [ $(sudo ${cephPkgs.ceph}/bin/rbd trash ls | ${pkgs.coreutils}/bin/wc -l) -ne 0 ]; then
                echo '`rbd trash ls`: Unexpected rbd images found in trash.' \
                  'We do not regularly use trash so far, contact the Infra' \
                  'team if you see a need to do so.'
              fi
            '';
            interval = 600;
          };
        };
        flyingcircus.services.ceph = {
          fc-ceph.settings =
            let
              monSettings = {
                release = role.cephRelease;
                path = cephPkgs.fc-ceph-path;
              };
            in
            {
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

          extraSettingsSections =
            lib.recursiveUpdate
              {
                mon = normaliseCephOptionAttrs defaultMonSettings;
                mgr = normaliseCephOptionAttrs defaultMgrSettings;
              }
              (
                lib.recursiveUpdate (normaliseCephOptionSection (
                  lib.foldr (attr: acc: acc // attr) { } (map perMonSettings (fclib.findServices "ceph_mon-mon"))
                )) { mon = normaliseCephOptionAttrs role.extraSettings; }
              );
        };

        systemd.services.fc-ceph-mon = rec {
          enable = !config.flyingcircus.services.ceph.server.passive;

          description = "Local Ceph Mon (via fc-ceph)";
          wantedBy = [ "multi-user.target" ];
          wants = [ fclib.network.sto.addressUnit ];
          requires = [ "network-online.target" ]; # PL-133952
          after = wants ++ requires;

          restartTriggers = [
            config.environment.etc."ceph/ceph.conf".source
            cephPkgs.ceph
          ];

          environment = {
            PYTHONUNBUFFERED = "1";
          };

          serviceConfig = {
            Type = "simple";
            ExecStart = " ${cephPkgs.fc-ceph}/bin/fc-ceph mon activate --as-systemd-unit";
            # try to restart after 5s for 6 attempts, afterwards wait for a minute between attempts
            Restart = "always";
            RestartSec = "5s";
            RestartSteps = 6;
            RestartMaxDelaySec = "1min";
          };
        };

        systemd.services.fc-ceph-load-vm-images = {
          description = "Load new VM base images";
          serviceConfig.Type = "oneshot";
          script = "${cephPkgs.fc-ceph}/bin/fc-ceph maintenance load-vm-images";
          environment = {
            PYTHONUNBUFFERED = "1";
          };
        };

        systemd.services.fc-ceph-purge-old-snapshots = {
          description = "Purge old snapshots";
          serviceConfig.Type = "oneshot";
          script = "${cephPkgs.fc-ceph}/bin/fc-ceph maintenance purge-old-snapshots";
          environment = {
            PYTHONUNBUFFERED = "1";
          };
        };

        systemd.services.fc-ceph-clean-deleted-vms = {
          description = "Purge old snapshots";
          serviceConfig.Type = "oneshot";
          script = "${cephPkgs.fc-ceph}/bin/fc-ceph maintenance clean-deleted-vms";
          environment = {
            PYTHONUNBUFFERED = "1";
          };
        };

        systemd.services.fc-ceph-mon-update-client-keys = {
          description = "Update client keys and authorization in the monitor database.";
          serviceConfig.Type = "oneshot";
          script = "${cephPkgs.fc-ceph}/bin/fc-ceph keys mon-update-client-keys";
          environment = {
            PYTHONUNBUFFERED = "1";
          };
        };

        systemd.services.fc-ceph-mgr = rec {
          enable = !config.flyingcircus.services.ceph.server.passive;

          description = "Local Ceph MGR (via fc-ceph)";
          wantedBy = [ "multi-user.target" ];
          wants = [ fclib.network.sto.addressUnit ];
          requires = [ "network-online.target" ]; # PL-133952
          after = wants ++ requires ++ [ "fc-ceph-mon.service" ];

          restartTriggers = [
            config.environment.etc."ceph/ceph.conf".source
            cephPkgs.ceph
          ];

          environment = {
            PYTHONUNBUFFERED = "1";
          };

          # imperatively ensure mgr modules.
          # preStart becuase these go via the mon.
          preStart = lib.concatStringsSep "\n" (
            lib.forEach mgrEnabledModules.${role.cephRelease} (
              mod: "${cephPkgs.ceph}/bin/ceph mgr module enable ${mod} --force"
            )
            ++ lib.forEach mgrDisabledModules.${role.cephRelease} (
              mod: "${cephPkgs.ceph}/bin/ceph mgr module disable ${mod}"
            )
          );
          # these settings require an active mgr
          postStart =
            let
              rg = lib.attrByPath [ "parameters" "resource_group" ] "" config.flyingcircus.enc;
              location = lib.attrByPath [ "parameters" "location" ] "" config.flyingcircus.enc;
            in
            ''
                # Wait until the mgr is available, can take up to 1 minute
                count=0
                while ! ${cephPkgs.ceph}/bin/ceph telemetry status
                do
                if [ $count -eq 21 ]
                then
                  echo "Tried 60 seconds, not able to contact mgr…"
                  exit 1
                fi

                echo "Failed to contact a ceph mgr after $count attempts. Waiting…"
                count=$((count+1))
                sleep 3
              done
            ''
            + (
              if role.mgr.sendTelemetry then
                ''
                  ${cephPkgs.ceph}/bin/ceph telemetry on --license sharing-1-0
                  ${cephPkgs.ceph}/bin/ceph config set mgr mgr/telemetry/contact 'Flying Circus IO <support@flyingcircus.io>'
                  ${cephPkgs.ceph}/bin/ceph config set mgr mgr/telemetry/description 'FCIO Cluster #${builtins.hashString "sha512" "${location}/${rg}"}'
                  ${cephPkgs.ceph}/bin/ceph config set mgr mgr/telemetry/channel_ident true
                ''
              else
                ''
                  ${cephPkgs.ceph}/bin/ceph telemetry off
                ''
            );

          serviceConfig = {
            Type = "simple";
            ExecStart = " ${cephPkgs.fc-ceph}/bin/fc-ceph mgr activate --as-systemd-unit";
            # try to restart after 5s for 6 attempts, afterwards wait for a minute between attempts
            Restart = "always";
            RestartSec = "5s";
            RestartSteps = 6;
            RestartMaxDelaySec = "1min";
          };
        };

      }
    ))

    (lib.mkIf (role.enable && role.primary) {

      systemd.timers.fc-ceph-load-vm-images = {
        enable = !config.flyingcircus.services.ceph.server.passive;

        description = "Timer for loading new VM base images";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "10m";
          OnUnitActiveSec = "10m";
        };
      };

      systemd.timers.fc-ceph-purge-old-snapshots = {
        enable = !config.flyingcircus.services.ceph.server.passive;

        description = "Timer for cleaning old snapshots";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1h";
          OnUnitActiveSec = "3h";
        };
      };

      systemd.timers.fc-ceph-clean-deleted-vms = {
        enable = !config.flyingcircus.services.ceph.server.passive;

        description = "Timer for cleaning deleted VM disks";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1h";
          OnUnitActiveSec = "3h";
        };
      };

      systemd.timers.fc-ceph-mon-update-client-keys = {
        enable = !config.flyingcircus.services.ceph.server.passive;

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
