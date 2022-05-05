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
          mon pg warn max per osd = 3000
          mon pg warn max object skew = 20

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
    };

    flyingcircus.services.ceph.client = {
      enable = lib.mkEnableOption "Ceph client";

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

  config = lib.mkIf cfg.client.enable {

    environment.systemPackages = [ pkgs.ceph ];

    boot.kernelModules = [ "rbd" ];

    systemd.tmpfiles.rules = [
      "d /run/ceph - root - - -"
      "d /var/log/ceph 0755 root - - -"
    ];

    services.udev.extraRules = ''
      KERNEL=="rbd[0-9]*", ENV{DEVTYPE}=="disk", PROGRAM="${pkgs.ceph}/bin/ceph-rbdnamer %k", SYMLINK+="rbd/%c{1}/%c{2}"
      KERNEL=="rbd[0-9]*", ENV{DEVTYPE}=="partition", PROGRAM="${pkgs.ceph}/bin/ceph-rbdnamer %k", SYMLINK+="rbd/%c{1}/%c{2}-part%n"
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
