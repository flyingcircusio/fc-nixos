{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  cfg = config.flyingcircus.services.ceph.client;
  static = config.flyingcircus.static.ceph;
in
{
  options = {
    flyingcircus.services.ceph.client = {
      enable = lib.mkEnableOption "Ceph client";
    };
  };

  config = lib.mkIf cfg.enable {

    environment.systemPackages = [ pkgs.ceph ];

    boot.kernelModules = [ "rbd" ];

    systemd.tmpfiles.rules = [
      "d '/run/ceph' - root - - -"
    ];

    environment.etc."ceph/ceph.conf".text = 
        let
            public_network = "172.20.4.0/24";
            cluster_network = "172.20.8.0/24";
            location = config.flyingcircus.enc.parameters.location;
            resource_group = config.flyingcircus.enc.parameters.resource_group;
            fs_id = static.fsids.${location}.${resource_group};
            mons = lib.concatMapStringsSep ","
                (mon: "${head (lib.splitString "." mon.address)}.sto.${location}.ipv4.gocept.net")
                (fclib.findServices "ceph_mon-mon");
        in ''
      [global]
      fsid = ${fs_id}

      public network = ${public_network}
      cluster network = ${cluster_network}

      pid file = /run/ceph/$type-$id.pid

      # Needs to correspond with daemon startup ulimit
      max open files = 262144

      osd pool default min size = 2
      osd pool default size = 3

      setuser match path = /srv/ceph/$type/$cluster-$id

      debug filestore = 4
      debug mon = 4
      debug osd = 4
      debug journal = 4
      debug throttle = 4

      mon compact on start = true     # Keep leveldb small
      mon host = ${mons}
      mon osd down out interval = 900  # Allow 15 min for reboots to happen without backfilling.
      mon osd nearfull ratio = .9

      [client]
      log file = /var/log/ceph/client.log
      rbd cache = true
      rbd default format = 2
      # The default default is 61, which enables all the new fancy features of jewel
      # which we are a) scared of due to performance concerns and because b)
      # we are not prepared to handle locking in this weird way ...
      rbd default features = 1
      admin socket = /run/ceph/rbd-$pid-$cctid.asok

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

      debug none = 4/5
      debug lockdep = 4/5
      debug context = 4/5
      debug crush = 4/5
      debug mds = 4/5
      debug mds balancer = 4/5
      debug mds locker = 4/5
      debug mds log = 4/5
      debug mds log expire = 4/5
      debug mds migrator = 4/5
      debug buffer = 4/5
      debug timer = 4/5
      debug filer = 4/5
      debug striper = 4/5
      debug objecter = 4/5
      debug rados = 4/5
      debug rbd = 4/5
      debug rbd mirror = 4/5
      debug rbd replay = 4/5
      debug journaler = 4/5
      debug objectcacher = 4/5
      debug client = 4/5
      debug osd = 4/5
      debug optracker = 4/5
      debug objclass = 4/5
      debug filestore = 4/5
      debug journal = 4/5
      debug ms = 0/5
      debug mon = 4/5
      debug monc = 4/5
      debug paxos = 4/5
      debug tp = 4/5
      debug auth = 4/5
      debug crypto = 4/5
      debug finisher = 4/5
      debug heartbeatmap = 4/5
      debug perfcounter = 4/5
      debug rgw = 4/5
      debug civetweb = 4/5
      debug javaclient = 4/5
      debug asok = 4/5
      debug throttle = 4/5
      debug refs = 0/5
      debug xio = 4/5
      debug compressor = 4/5
      debug newstore = 4/5
      debug bluestore = 4/5
      debug bluefs = 4/5
      debug bdev = 4/5
      debug kstore = 4/5
      debug rocksdb = 4/5
      debug leveldb = 4/5
      debug kinetic = 4/5
      debug fuse = 4/5
      '';

    environment.etc."ceph/ceph.client.${config.networking.hostName}.keyring".source = 
      pkgs.runCommandLocal "ceph-client-keyring" {} ''
      key=''$(${pkgs.python3Full}/bin/python3 ${./generate-key.py} ${config.flyingcircus.enc.parameters.secret_salt})
      cat > $out <<__EOF__
      [client.${config.networking.hostName}]
      key = ''${key}
      __EOF__
    '';

  };

}
