{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.services.ceph;
  fclib = config.fclib;
  static = config.flyingcircus.static.ceph;
  public_network = head fclib.network.sto.v4.networks;
  location = config.flyingcircus.enc.parameters.location;
  resource_group = config.flyingcircus.enc.parameters.resource_group;
  fs_id = static.fsids.${location}.${resource_group};
  mons = lib.concatMapStringsSep ","
    (mon: "${head (lib.splitString "." mon.address)}.sto.${location}.ipv4.gocept.net")
    (fclib.findServices "ceph_mon-mon");

in
{
  options = {

    flyingcircus.services.ceph = {
      config = lib.mkOption {
        type = lib.types.lines;
        default = ''
          [global]
          fsid = ${fs_id}

          public network = ${public_network}
          ${if cfg.cluster_network != null then "cluster network = " + cfg.cluster_network else "; cluster network not available on pure clients"}

          pid file = /run/ceph/$type-$id.pid
          admin socket = /run/ceph/$cluster-$name.asok

          # Needs to correspond with daemon startup ulimit
          max open files = 262144

          osd pool default min size = 2
          osd pool default size = 3

          osd pool default pg num = 64
          osd pool default pgp num = 64

          setuser match path = /srv/ceph/$type/ceph-$id

          debug filestore = 4
          debug mon = 4
          debug osd = 4
          debug journal = 4
          debug throttle = 4

          mon compact on start = true     # Keep leveldb small
          mon host = ${mons}
          mon osd down out interval = 900  # Allow 15 min for reboots to happen without backfilling.
          mon osd nearfull ratio = .9

          mon data = /srv/ceph/mon/$cluster-$id
          mon osd allow primary affinity = true
          mon pg warn max object skew = 20

          mgr data = /srv/ceph/mgr/$cluster-$id
        '';
        description = ''
          Global config of the Ceph config file. Will be used
          for all Ceph daemons and binaries.
        '';
      };
      extraConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          Extra config in the [global] section.
        '';
      };
      cluster_network = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      fc-ceph = {
        settings = lib.mkOption {
          type = with lib.types; attrsOf (attrsOf (oneOf [ bool int str package ]));
          default = { };
          description = "Configuration for the fc-ceph utility, will be turned into the contents of /etc/ceph/fc-ceph.conf";
        };
      };

      client = {
        enable = lib.mkEnableOption "Ceph client";

        cephRelease = lib.mkOption {
          type = fclib.ceph.highestCephReleaseType;
          description = "Ceph release series that the main package belongs to. "
            + "This option behaves special in a way that, if defined multiple times, the latest release name will be chosen.";
          default = fclib.ceph.defaultRelease;
        };

        package = lib.mkOption {
          type = lib.types.package;
          description = "Main ceph package to be used on the system and to be put into PATH. "
            + "The package set must belong to the release series defined in the `cephRelease` option. "
            + "Only modify if really necessary, otherwise the default ceph package from the defined series is used.";
          default =  fclib.ceph.releasePkgs.${cfg.client.cephRelease};
        };

        config = lib.mkOption {
          type = lib.types.lines;
          default = ''
            [client]
            log file = /var/log/ceph/client.log
            rbd cache = true
            rbd default format = 2
            # The default default is 61, which enables all the new fancy features of jewel
            # which we are a) scared of due to performance concerns and because b)
            # we are not prepared to handle locking in this weird way ...
            rbd default features = 1
            admin socket = /run/ceph/rbd-$pid-$cctid.asok
          '';
          description = ''
            Contents of the Ceph config file for clients.
          '';
        };
      };
    };
  };

  config = lib.mkIf cfg.client.enable {

    assertions = [
      {
        assertion = (cfg.client.package.codename == cfg.client.cephRelease);
        message = "The ceph package set for this ceph client service must be of the same release series as defined in `cephRelease`";
      }
    ];

    # config file to be read by fc-ceph
    environment.etc."ceph/fc-ceph.conf".text = lib.generators.toINI { } cfg.fc-ceph.settings;

    # build a default binary path for fc-ceph
    flyingcircus.services.ceph.fc-ceph.settings.default = {
      release = cfg.client.cephRelease;
      path = fclib.ceph.fc-ceph-path cfg.client.package;
    };
    environment.systemPackages = [ cfg.client.package ];

    boot.kernelModules = [ "rbd" ];

    systemd.tmpfiles.rules = [
      "d /run/ceph - root - - -"
      "d /var/log/ceph 0755 root - - -"
    ];

    services.udev.extraRules = ''
      KERNEL=="rbd[0-9]*", ENV{DEVTYPE}=="disk", PROGRAM="${cfg.client.package}/bin/ceph-rbdnamer %k", SYMLINK+="rbd/%c{1}/%c{2}"
      KERNEL=="rbd[0-9]*", ENV{DEVTYPE}=="partition", PROGRAM="${cfg.client.package}/bin/ceph-rbdnamer %k", SYMLINK+="rbd/%c{1}/%c{2}-part%n"
    '';

    environment.etc."ceph/ceph.conf".text =
      (cfg.config + "\n" + cfg.extraConfig + "\n" + cfg.client.config);

    environment.variables.CEPH_ARGS = fclib.mkPlatform "--id ${config.networking.hostName}";

    flyingcircus.activationScripts.ceph-client-keyring = ''
      ${pkgs.fc.ceph}/bin/fc-ceph keys generate-client-keyring
    '';

    services.logrotate.extraConfig = ''
      /var/log/ceph/client.log {
          rotate 30
          create 0644 root adm
          copytruncate
      }
    '';

  };

}
