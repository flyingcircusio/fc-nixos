{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  role = config.flyingcircus.roles.ceph_rgw;
  enc = config.flyingcircus.enc;

  username = "client.radosgw.${config.networking.hostName}";

  # We do not have service data during bootstrapping.
  rgws = (sort lessThan (map (service: service.address) (fclib.findServices "ceph_rgw-server")));
  first_rgw = if rgws == [] then "" else head (lib.splitString "." (head rgws));

in
{
  options = {
    flyingcircus.roles.ceph_rgw = {
      enable = lib.mkEnableOption "CEPH Rados Gateway";
      supportsContainers = fclib.mkDisableContainerSupport;

      primary = lib.mkOption {
        default = (first_rgw == config.networking.hostName);
        description = "Primary monitors take over additional maintenance tasks.";
        type = lib.types.bool;
       };

      config = lib.mkOption {
        type = lib.types.lines;
        default = let
              mon_addrs = lib.concatMapStringsSep ","
                  (mon: "${head (filter fclib.isIp4 mon.ips)}:${mon_port}")
                  (fclib.findServices "ceph_mon-mon");
            in ''
          [${username}]
          host = ${config.networking.hostName}
          keyring = /etc/ceph/ceph.${username}.keyring
          log file = /var/log/ceph/client.radosgw.log
          pid file = /run/ceph/radosgw.pid
          admin socket = /run/ceph/radosgw.asok
          rgw data = /srv/ceph/radosgw/ceph-$id
          rgw enable ops log = false
          debug rgw = 4 5
          debug civetweb = 4 5
          debug rados = 4 5
          '';
        description = ''
          Contents of the Ceph config file for RGWs.
        '';
      };

    };
  };

  config = lib.mkMerge [ 
    (lib.mkIf role.enable {

      flyingcircus.services.ceph.server.enable = true;

      environment.etc."ceph/ceph.conf".text = lib.mkAfter role.config;

      systemd.tmpfiles.rules = [
          "d /srv/ceph/radosgw 2775 root service"
      ];

      systemd.services.fc-ceph-rgw = rec {
        description = "Start/stop local Ceph Rados Gateway";
        wantedBy = [ "multi-user.target" ];
        # Ceph requires the IPs to be properly attached to interfaces so it
        # knows where to bind to the public and cluster networks.
        wants = [ "network.target" ];
        after = wants;

        environment = {
          PYTHONUNBUFFERED = "1";
        };

        restartIfChanged = true;

        serviceConfig = {
            Type = "simple";
            Restart = "always";
            ExecStart = "${pkgs.ceph}/bin/radosgw -n ${username} -f -c /etc/ceph/ceph.conf";
        };
      };

      networking.firewall.extraCommands = let
        srv = fclib.network.srv;
      in ''
        # Accept traffic from S3 gateways from within the SRV network.

      '' + (lib.concatMapStringsSep "\n"
              (net: "iptables -A nixos-fw -i ${srv.device} -s ${net} -p tcp --dport 7480 -j ACCEPT")
              srv.v4.networks
      ) + "\n" +
      (lib.concatMapStringsSep "\n"
              (net: "ip6tables -A nixos-fw -i ${srv.device} -s ${net} -p tcp --dport 7480 -j ACCEPT")
              srv.v6.networks);

      systemd.services.fc-ceph-rgw-update-stats = {
        description = "Update RGW stats";
        serviceConfig.Type = "oneshot";
        path = [ pkgs.ceph pkgs.jq ];
        script = ''
          for uid in $(radosgw-admin metadata list user | jq -r '.[]'); do
            echo $uid
            radosgw-admin user stats --uid  $uid --sync-stats
          done
        '';
      }; 

    })

    (lib.mkIf (role.enable && role.primary) {

      systemd.timers.fc-ceph-rgw-update-stats = {
        description = "Timer for updating RGW stats";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "10m";
          OnUnitActiveSec = "10m";
        };
      };

    })

  ];

}
