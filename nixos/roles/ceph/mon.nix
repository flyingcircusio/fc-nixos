{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  role = config.flyingcircus.roles.ceph_mon;
  enc = config.flyingcircus.enc;
  inherit (fclib.ceph) expandCamelCaseAttrs expandCamelCaseSection;

  mons = (sort lessThan (map (service: service.address) (fclib.findServices "ceph_mon-mon")));
  # We do not have service data during bootstrapping.
  first_mon = if mons == [ ] then "" else head (lib.splitString "." (head mons));

  fc-check-ceph-withVersion = pkgs.fc.check-ceph.${role.cephRelease};
  fc-ceph = pkgs.fc.cephWith fclib.ceph.releasePkgs.${role.cephRelease}.ceph;

  # default definitions for the mgr.* options:
  mgrEnabledModules = {
    luminous = [ "balancer" "dashboard" "status" ];
    # always_on_modules are not listed here
    nautilus = [
      "telemetry"
      "iostat"
    ];
  };
  mgrDisabledModules = {
    luminous = [];
    nautilus = [
      "restful"
    ];
  };
  defaultMonSettings = {
    # A value < 1 would generate health warnings despite the scrub deadlines still being
    # below their max limit
    monWarnPgNotScrubbedRatio = 1;
    monWarnPgNotDeepScrubbedRatio = 1;
  };
  perMonSettings = mon:
  let
    id = head (lib.splitString "." mon.address);
    # we have always been using the default mon ports, so there is no need
    # to explicitly specify a port
    addr = toString (head (filter fclib.isIp4 mon.ips));
  in
  { "mon.${id}" = {
    host = id;
    publicAddr = addr;
  };};
  defaultMgrSettings = {
    mgrInitialModules = lib.concatStringsSep " " mgrEnabledModules.${role.cephRelease};
  };
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
        default = "";
        description = ''
          Contents of the Ceph config file for MONs.
        '';
      };
      extraSettings = lib.mkOption {
        type = with lib.types; attrsOf (oneOf [ str int float bool ]);
        default = {};   # defaults are provided in the config section with a lower priority
        description = ''
          mon config of the Ceph config file.
          Can override existing default setting values. Configuration keys like `mon osd full ratio`''
          + '' can alternatively be written in camelCase as `monOsdFullRatio`.
        '';
      };

      cephRelease = fclib.ceph.releaseOption // {
        description = "Codename of the Ceph release series used for the the mon package.";
      };

      mgr = {
        enabledModules = lib.mkOption {
          type = with lib.types; listOf str;
          default = mgrEnabledModules."${role.cephRelease}";
          description = "Modules to be explicitly activated via this config,"
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
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf role.enable {
      assertions = [
        {
          assertion = (
            ( role.extraSettings != {}
            || config.flyingcircus.services.ceph.extraSettings != {}
            || config.flyingcircus.services.ceph.client.extraSettings != {}
            ) -> role.config == "");
          message = "Mixing the configuration styles (extra)Config and (extra)Settings is unsupported, please use either plaintext config or structured settings for ceph.";
        }
      ];
      flyingcircus.services.ceph = {
        fc-ceph.settings = let
          monSettings =  {
            release = role.cephRelease;
            path = fclib.ceph.fc-ceph-path fclib.ceph.releasePkgs.${role.cephRelease}.ceph;
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

      systemd.services.fc-ceph-mon = rec {
        description = "Local Ceph Mon (via fc-ceph)";
        wantedBy = [ "multi-user.target" ];
        # Ceph requires the IPs to be properly attached to interfaces so it
        # knows where to bind to the public and cluster networks.
        wants = [ "network.target" ];
        after = wants;

        restartTriggers = [
          config.environment.etc."ceph/ceph.conf".source
          fclib.ceph.releasePkgs.${role.cephRelease}.ceph
        ];

        environment = {
          PYTHONUNBUFFERED = "1";
        };

        script = ''
          ${fc-ceph}/bin/fc-ceph mon activate
        '';

        reload = ''
          ${fc-ceph}/bin/fc-ceph mon reactivate
        '';

        preStop = ''
          ${fc-ceph}/bin/fc-ceph mon deactivate
        '';

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };

      flyingcircus.passwordlessSudoRules = [
        {
          commands = [
            "${fc-check-ceph-withVersion}/bin/check_ceph"
          ];
          groups = [ "sensuclient" ];
        }
      ];

      flyingcircus.services.sensu-client.checks = {
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
        script = "${fc-ceph}/bin/fc-ceph maintenance load-vm-images";
        environment = {
          PYTHONUNBUFFERED = "1";
        };
      };

      systemd.services.fc-ceph-purge-old-snapshots = {
        description = "Purge old snapshots";
        serviceConfig.Type = "oneshot";
        script = "${fc-ceph}/bin/fc-ceph maintenance purge-old-snapshots";
        environment = {
          PYTHONUNBUFFERED = "1";
        };
      };

      systemd.services.fc-ceph-clean-deleted-vms = {
        description = "Purge old snapshots";
        serviceConfig.Type = "oneshot";
        script = "${fc-ceph}/bin/fc-ceph maintenance clean-deleted-vms";
        environment = {
          PYTHONUNBUFFERED = "1";
        };
      };

      systemd.services.fc-ceph-mon-update-client-keys = {
        description = "Update client keys and authorization in the monitor database.";
        serviceConfig.Type = "oneshot";
        script = "${fc-ceph}/bin/fc-ceph keys mon-update-client-keys";
        environment = {
          PYTHONUNBUFFERED = "1";
        };
      };

    })
    (lib.mkIf (role.enable && role.config == "") {
      flyingcircus.services.ceph.extraSettingsSections = lib.recursiveUpdate
      { mon = expandCamelCaseAttrs defaultMonSettings; }
      (lib.recursiveUpdate
        (expandCamelCaseSection (lib.foldr (attr: acc: acc // attr) { } (map perMonSettings (fclib.findServices "ceph_mon-mon"))))
        (lib.recursiveUpdate
          { mon = expandCamelCaseAttrs role.extraSettings; }
          (lib.optionalAttrs (fclib.ceph.releaseAtLeast "luminous" role.cephRelease) {
            mon = expandCamelCaseAttrs defaultMgrSettings;
          })
        )
      );
    })

    (lib.mkIf (role.enable && role.config != "") {
      environment.etc."ceph/ceph.conf".text = lib.mkAfter role.config;
    })
    (lib.mkIf (role.enable && fclib.ceph.releaseAtLeast "luminous" role.cephRelease ) {
      systemd.services.fc-ceph-mgr = rec {
        description = "Local Ceph MGR (via fc-ceph)";
        wantedBy = [ "multi-user.target" ];
        # Ceph requires the IPs to be properly attached to interfaces so it
        # knows where to bind to the public and cluster networks.
        wants = [ "network.target" ];
        after = wants;

        restartTriggers = [
          config.environment.etc."ceph/ceph.conf".source
          fclib.ceph.releasePkgs.${role.cephRelease}.ceph
        ];

        environment = {
          PYTHONUNBUFFERED = "1";
        };

        script = ''
          ${fc-ceph}/bin/fc-ceph mgr activate
        '';

        reload = ''
          ${fc-ceph}/bin/fc-ceph mgr reactivate
        '';

        preStart =
          # dashboard only enabled for luminous, as the Nautilus release fails to build in the sandbox so far.
          # If we ever manage to get it enabled, `ceph config set` needs to be used instead of `ceph config-key`
          lib.optionalString (role.cephRelease == "luminous") ''
            echo "ensure mgr dashboard binds to localhost only"
            # make _all_ hosts bind the dashboard to localhost (v4) only (default port: 7000)
            ${fclib.ceph.releasePkgs.${role.cephRelease}.ceph}/bin/ceph config-key set mgr/dashboard/server_addr 127.0.0.1
          ''
          # imperatively ensure mgr modules
          + lib.concatStringsSep "\n" (
              lib.forEach mgrEnabledModules.${role.cephRelease} (mod: "${fclib.ceph.releasePkgs.${role.cephRelease}.ceph}/bin/ceph mgr module enable ${mod} --force")
            )
          + "\n"
          + lib.concatStringsSep "\n" (
              lib.forEach mgrDisabledModules.${role.cephRelease} (mod: "${fclib.ceph.releasePkgs.${role.cephRelease}.ceph}/bin/ceph mgr module disable ${mod}")
            )
          ;

        preStop = ''
          ${fc-ceph}/bin/fc-ceph mgr deactivate
        '';

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };
    })
    (lib.mkIf (role.enable && fclib.ceph.releaseAtLeast "nautilus" role.cephRelease ) {
      flyingcircus.passwordlessSudoRules = [
        {
          commands = [
            "${fc-check-ceph-withVersion}/bin/check_snapshot_restore_fill"
          ];
          groups = [ "sensuclient" ];
        }
      ];

      flyingcircus.services.sensu-client.checks = let
          # check config generated directly from our platform settings
          configtoml = (pkgs.formats.toml {}).generate "config.toml" {
            thresholds = {
              # use canonical, non-camelCase form of ceph settings
              nearfull = config.flyingcircus.services.ceph.allMergedSettings.mon."mon osd nearfull ratio";
              full = config.flyingcircus.services.ceph.allMergedSettings.mon."mon osd full ratio";
            };
            # FIXME: is hardcoding this okay?
            ceph_roots = {
              default = [ "rbd.hdd" ];
              ssd = [ "rbd.ssd" ];
            };
          };
        in {
          ceph_snapshot_restore_fill = {
            notification = "There is enough space to be able to restore the largest " +
              "RBD snapshot. (does not consider sparse allocation)";
            command = "sudo ${fc-check-ceph-withVersion}/bin/check_snapshot_restore_fill ${configtoml}";
            interval = 600;
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
