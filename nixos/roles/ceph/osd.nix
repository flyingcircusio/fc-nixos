{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  role = config.flyingcircus.roles.ceph_osd;
  enc = config.flyingcircus.enc;
  inherit (fclib.ceph) expandCamelCaseAttrs expandCamelCaseSection;

  fc-ceph = pkgs.fc.cephWith fclib.ceph.releasePkgs.${role.cephRelease}.ceph;

  defaultOsdSettings = {
    # Assist speedy but balanced recovery
    osdMaxBackfills = 2;
    osdOpQueue = "wpq";
    osdOpQueueCutOff = "high";
    filestoreQueueMaxOps = 500;

    # Disable new (luminous) automatic crush map organisation according to
    # (auto detected) device classes for now.
    osdCrushUpdateOnStart = false;

    # automatically repairing PGs at scrub mismatches is reliable due to Bluestore
    # internal checksumming
    osdScrubAutoRepair = true;
    # we use the default value of max. number of automatically corrected errors
    # "osd_scrub_auto_repair_num_errors": "5",

    # Various

    msDispatchThrottleBytes = 1048576000;

    osdPgEpochPersistedMaxStale = 150;
    osdClientMessageCap = 10000;
    osdSnapTrimSleep = 0.25;

    osdMapCacheSize = 200;
    osdMapMaxAdvance = 150;
    osdMapShareMaxEpochs = 100;

    # increased to survive router reboots
    osdOpThreadSuicideTimeout = 300;

    # Logging/Debugging - silent enough for practical day-to-day operations
    # but verbose enough to be able to respond/analyze issues when they arise

    osdOpHistorySize = 1000;
    osdOpHistoryDuration = 43200;

    # we currently have (too) many PGs in our pools, make sure the cluster still
    # functions even when some osds are missing
    osdMaxPgPerOsdHardRatio = 5;

    debugNone = "1/5";
    debugLockdep = "1/5";
    debugContext = "1/5";
    debugCrush = "1/5";
    debugMds = "1/5";
    debugMdsBalancer = "1/5";
    debugMdsLocker = "1/5";
    debugMdsLog = "1/5";
    debugMdsLogExpire = "1/5";
    debugMdsMigrator = "1/5";
    debugBuffer = "1/5";
    debugTimer = "1/5";
    debugFiler = "1/5";
    debugStriper = "1/5";
    debugObjecter = "1/5";
    debugRados = "1/5";
    debugRbd = "1/5";
    debugRbdMirror = "1/5";
    debugRbdReplay = "1/5";
    debugJournaler = "1/5";
    debugObjectcacher = "1/5";
    debugClient = "1/5";
    debugOsd = "1/5";
    debugOptracker = "1/5";
    debugObjclass = "1/5";
    debugFilestore = "1/5";
    debugJournal = "1/5";
    debugMs = "0/5";
    debugMon = "1/5";
    debugMonc = "1/5";
    debugPaxos = "1/5";
    debugTp = "1/5";
    debugAuth = "1/5";
    debugCrypto = "1/5";
    debugFinisher = "1/5";
    debugHeartbeatmap = "1/5";
    debugPerfcounter = "1/5";
    debugRgw = "1/5";
    debugCivetweb = "1/5";
    debugJavaclient = "1/5";
    debugAsok = "1/5";
    debugThrottle = "1/5";
    debugRefs = "0/5";
    debugXio = "1/5";
    debugCompressor = "1/5";
    debugNewstore = "1/5";
    debugBluestore = "1/5";
    debugBluefs = "1/5";
    debugBdev = "1/5";
    debugKstore = "1/5";
    debugRocksdb = "1/5";
    debugLeveldb = "1/5";
    debugKinetic = "1/5";
    debugFuse = "1/5";
  };
in
{
  options = {
    flyingcircus.roles.ceph_osd = {
      enable = lib.mkEnableOption "CEPH OSD";
      supportsContainers = fclib.mkDisableContainerSupport;

      # This option can be used to disable automatic reactivation, e.g.
      # if you're working on a system and don't want to get (slow) reloads
      # blocking agent runs all the time.
      reactivate = lib.mkOption {
        default = true;
        description = "Reload OSDs during agent run.";
        type = lib.types.bool;
      };

      config = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          Contents of the Ceph config file for OSDs.
        '';
      };

      extraSettings = lib.mkOption {
        type = with lib.types; attrsOf (oneOf [ str int float bool ]);
        default = {};   # defaults are provided in the config section with a lower priority
        description = ''
          osd config section of the Ceph config file.
          Can override existing default setting values. Configuration keys like `mon osd full ratio`''
          + '' can alternatively be written in camelCase as `monOsdFullRatio`.
        '';
      };

      cephRelease = fclib.ceph.releaseOption // {
        description = "Codename of the Ceph release series used for the the osd package.";
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
        server = {
          enable = true;
          cephRelease = role.cephRelease;
        };

        fc-ceph.settings = let
          osdSettings =  {
            release = role.cephRelease;
            path = fclib.ceph.fc-ceph-path fclib.ceph.releasePkgs.${role.cephRelease}.ceph;
          };
        in {
          # fc-ceph OSD
          OSDManager = osdSettings;
          # The MaintenanceTasks module uses the `rbd` binary. While it'd be safer to handle it's
          # ceph version separately, for now just pragmatically follow the OSD version as
          # by then both OSDs and MONs are already updated.
          MaintenanceTasks = osdSettings;
          };
      };

      flyingcircus.services.ceph.cluster_network = head fclib.network.stb.v4.networks;

      systemd.services.fc-ceph-osds = rec {
        description = "All locally known Ceph OSDs (via fc-ceph managed units)";
        wantedBy = [ "multi-user.target" ];
        # Ceph requires the IPs to be properly attached to interfaces so it
        # knows where to bind to the public and cluster networks.
        wants = [ "network.target" ];
        after = wants;

        environment = {
          PYTHONUNBUFFERED = "1";
        };

        restartIfChanged = false;

        script = ''
          ${fc-ceph}/bin/fc-ceph osd activate all
        '';

        reload = lib.optionalString role.reactivate ''
          ${fc-ceph}/bin/fc-ceph osd reactivate all
        '';

        preStop = ''
          ${fc-ceph}/bin/fc-ceph osd deactivate all
        '';

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };

      systemd.services."fc-ceph-osd@" = rec {
        description = "Ceph OSD %i";
        # Ceph requires the IPs to be properly attached to interfaces so it
        # knows where to bind to the public and cluster networks.
        wants = [ "network.target" ];
        after = wants;

        environment = {
          PYTHONUNBUFFERED = "1";
        };

        restartIfChanged = false;

        serviceConfig = {
          Type = "forking";
          Restart = "always";
          PIDFile = "/run/ceph/osd.%i.pid";
          ExecStart = ''
            ${fc-ceph}/bin/fc-ceph osd activate --as-systemd-unit  %i
          '';
          ExecStop = ''
            ${fc-ceph}/bin/fc-ceph osd deactivate --as-systemd-unit %i
          '';
        };

      };


    })
    (lib.mkIf (role.enable && role.config == "") {
      flyingcircus.services.ceph.extraSettingsSections.osd = lib.recursiveUpdate
        (expandCamelCaseAttrs defaultOsdSettings) (expandCamelCaseAttrs role.extraSettings);
    })
    (lib.mkIf (role.enable && role.config != "") {
      environment.etc."ceph/ceph.conf".text = lib.mkAfter role.config;
    })
    ];
}
