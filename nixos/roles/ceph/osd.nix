{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  role = config.flyingcircus.roles.ceph_osd;
  enc = config.flyingcircus.enc;

in
{
  options = {
    flyingcircus.roles.ceph_osd = {
      enable = lib.mkEnableOption "CEPH OSD";

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
        default = ''
          [osd]
          osd deep scrub interval = 1209600
          osd max scrubs = 1
          osd scrub chunk max = 1
          osd scrub chunk min = 1
          osd scrub interval randomize ratio = 1.0
          osd scrub load threshold = 2
          osd scrub max interval = 4838400
          osd scrub min interval = 2419200
          osd scrub sleep = 0.1
          osd scrub priority = 1
          osd requested scrub priority = 1

          # Assist speedy but balanced recovery
          osd max backfills = 2
          osd op queue = wpq
          osd op queue cut off = high
          filestore queue max ops = 500

          # Various

          ms dispatch throttle bytes = 1048576000

          osd pg epoch persisted max stale = 150
          osd client message cap = 10000
          osd snap trim sleep = 0.25

          osd map cache size = 200
          osd map max advance = 150
          osd map share max epochs = 100

          # increased to survive router reboots
          osd op thread suicide timeout = 300

          # Logging/Debugging - silent enough for practical day-to-day operations
          # but verbose enough to be able to respond/analyze issues when they arise

          osd op history size = 1000
          osd op history duration = 43200

          debug none = 1/5
          debug lockdep = 1/5
          debug context = 1/5
          debug crush = 1/5
          debug mds = 1/5
          debug mds balancer = 1/5
          debug mds locker = 1/5
          debug mds log = 1/5
          debug mds log expire = 1/5
          debug mds migrator = 1/5
          debug buffer = 1/5
          debug timer = 1/5
          debug filer = 1/5
          debug striper = 1/5
          debug objecter = 1/5
          debug rados = 1/5
          debug rbd = 1/5
          debug rbd mirror = 1/5
          debug rbd replay = 1/5
          debug journaler = 1/5
          debug objectcacher = 1/5
          debug client = 1/5
          debug osd = 1/5
          debug optracker = 1/5
          debug objclass = 1/5
          debug filestore = 1/5
          debug journal = 1/5
          debug ms = 0/5
          debug mon = 1/5
          debug monc = 1/5
          debug paxos = 1/5
          debug tp = 1/5
          debug auth = 1/5
          debug crypto = 1/5
          debug finisher = 1/5
          debug heartbeatmap = 1/5
          debug perfcounter = 1/5
          debug rgw = 1/5
          debug civetweb = 1/5
          debug javaclient = 1/5
          debug asok = 1/5
          debug throttle = 1/5
          debug refs = 0/5
          debug xio = 1/5
          debug compressor = 1/5
          debug newstore = 1/5
          debug bluestore = 1/5
          debug bluefs = 1/5
          debug bdev = 1/5
          debug kstore = 1/5
          debug rocksdb = 1/5
          debug leveldb = 1/5
          debug kinetic = 1/5
          debug fuse = 1/5
          '';
        description = ''
          Contents of the Ceph config file for OSDs.
        '';
      };

    };

  };

  config = lib.mkIf role.enable {

    flyingcircus.services.ceph.server.enable = true;

    environment.etc."ceph/ceph.conf".text = lib.mkAfter role.config;

    systemd.services.fc-ceph-osds = rec {
      description = "Start/stop local Ceph OSDs (via fc-ceph)";
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
          ${pkgs.fc.ceph}/bin/fc-ceph osd activate all
      '';

      reload = lib.optionalString role.reactivate ''
          ${pkgs.fc.ceph}/bin/fc-ceph osd reactivate all
      '';

      preStop = ''
         ${pkgs.fc.ceph}/bin/fc-ceph osd deactivate all
      '';

      serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
      };
    };

  };
}
