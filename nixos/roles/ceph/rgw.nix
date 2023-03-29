{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  role = config.flyingcircus.roles.ceph_rgw;
  enc = config.flyingcircus.enc;
  inherit (fclib.ceph) expandCamelCaseAttrs expandCamelCaseSection;

  username = "client.radosgw.${config.networking.hostName}";

  # We do not have service data during bootstrapping.
  rgws = (sort lessThan (map (service: service.address) (fclib.findServices "ceph_rgw-server")));
  first_rgw = if rgws == [ ] then "" else head (lib.splitString "." (head rgws));

  defaultRgwSettings = {
    host = config.networking.hostName;
    keyring = "/etc/ceph/ceph.${username}.keyring";
    logFile = "/var/log/ceph/client.radosgw.log";
    pidFile = "/run/ceph/radosgw.pid";
    adminSocket = "/run/ceph/radosgw.asok";
    rgwData = "/srv/ceph/radosgw/ceph-$id";
    rgwEnableOpsLog = false;
    rgwMimeTypesFile = "${pkgs.mime-types}/etc/mime.types";
    # FIXME: use different frontend in Nautilus
    rgwFrontends = "civetweb port=80";
    debugRgw = "0 5";
    debugCivetweb = "1 5";
    debugRados = "1 5";
  };
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
        default = "";
        description = ''
          Contents of the Ceph config file for RGWs.
        '';
      };

      extraSettings = lib.mkOption {
        type = with lib.types; attrsOf (oneOf [ str int float bool ]);
        default = {};   # defaults are provided in the config section with a lower priority
        description = ''
          config section of the Ceph config file of the radosgw client user.
          Can override existing default setting values. Configuration keys like `mon osd full ratio`''
          + '' can alternatively be written in camelCase as `monOsdFullRatio`.
        '';
      };

      cephRelease = fclib.ceph.releaseOption // {
        description = "Codename of the Ceph release series used for the the rgw package.";
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

      flyingcircus.services.ceph.server = {
        enable = true;
        cephRelease = role.cephRelease;
        # no fc-ceph settings necessary so far
      };

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
        restartTriggers = [ config.environment.etc."ceph/ceph.conf".source ];

        serviceConfig = {
          Type = "simple";
          Restart = "always";
          ExecStart = "${fclib.ceph.releasePkgs.${role.cephRelease}.ceph}/bin/radosgw -n ${username} -f -c /etc/ceph/ceph.conf";
        };
      };

      networking.firewall.extraStopCommands = ''
        ip46tables -w -t nat -D PREROUTING -j fc-nat-pre 2>/dev/null|| true
        ip46tables -w -t nat -F fc-nat-pre 2>/dev/null || true
        ip46tables -w -t nat -X fc-nat-pre 2>/dev/null || true
      '';

      networking.firewall.extraCommands =
        let
          srv = fclib.network.srv;
        in
        ''
          set -x
          # Accept traffic from S3 gateways from within the SRV network.
          ip46tables -w -t nat -N fc-nat-pre

        '' + (lib.concatMapStringsSep "\n"
          (net: ''
            iptables -A nixos-fw -i ${srv.device} -s ${net} -p tcp --dport 80 -j ACCEPT
            # PL-130368 Fix S3 presigned URLs
            iptables -t nat -A fc-nat-pre -p tcp --dport 7480 -j REDIRECT --to-port 80
          '')
          srv.v4.networks
        ) + "\n" +
        (lib.concatMapStringsSep "\n"
          (net: ''
            ip6tables -A nixos-fw -i ${srv.device} -s ${net} -p tcp --dport 80 -j ACCEPT
            # PL-130368 Fix S3 presigned URLs
            ip6tables -t nat -A fc-nat-pre -p tcp --dport 7480 -j REDIRECT --to-port 80
          '')
          srv.v6.networks) +
        ''
          ip46tables -t nat -A PREROUTING -j fc-nat-pre
        '';

      systemd.services.fc-ceph-rgw-update-stats = {
        description = "Update RGW stats";
        serviceConfig.Type = "oneshot";
        path = [ fclib.ceph.releasePkgs.${role.cephRelease}.ceph pkgs.jq ];
        script = ''
          for uid in $(radosgw-admin metadata list user | jq -r '.[]'); do
            echo $uid
            radosgw-admin user stats --uid  $uid --sync-stats
          done
        '';
      };

      services.logrotate.extraConfig = ''
        /var/log/ceph/client.radosgw.log {
            create 0644 root adm
            postrotate
              systemctl kill -s SIGHUP fc-ceph-rgw
            endscript
        }
      '';

    })

    (lib.mkIf (role.enable && role.config == "") {
        flyingcircus.services.ceph.extraSettingsSections.${username} = lib.recursiveUpdate
        (expandCamelCaseAttrs defaultRgwSettings) (expandCamelCaseAttrs role.extraSettings);
    })

    (lib.mkIf (role.enable && role.config != "") {
      environment.etc."ceph/ceph.conf".text = lib.mkAfter role.config;
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
