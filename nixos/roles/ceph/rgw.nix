{
  config,
  lib,
  pkgs,
  ...
}:

with builtins;

let
  fclib = config.fclib;
  role = config.flyingcircus.roles.ceph_rgw;
  enc = config.flyingcircus.enc;
  inherit (fclib.ceph) normaliseCephOptionAttrs normaliseCephOptionSection releaseAtLeast;
  bucketNameValidationPy = pkgs.writers.writePython3BinFromFile ./rgw-check-bucket-names.py {
    flakeIgnore = [ "E501" ];
  };
  rgw-validate-bucket-names = pkgs.writeShellScriptBin "rgw-validate-bucket-names" ''
    radosgw-admin bucket list | ${lib.getExe bucketNameValidationPy}
  '';

  username = "client.radosgw.${config.networking.hostName}";

  # We do not have service data during bootstrapping.
  rgws = (sort lessThan (map (service: service.address) (fclib.findServices "ceph_rgw-server")));
  first_rgw = if rgws == [ ] then "" else head (lib.splitString "." (head rgws));

  cephPkgs = fclib.ceph.mkPkgs role.cephRelease;

  defaultRgwSettings = {
    host = config.networking.hostName;
    keyring = "/etc/ceph/ceph.${username}.keyring";
    logFile = "/var/log/ceph/client.radosgw.log";
    pidFile = "/run/ceph/radosgw.pid";
    adminSocket = "/run/ceph/radosgw.asok";
    rgwData = "/srv/ceph/radosgw/ceph-$id";
    rgwEnableOpsLog = true;
    rgwOpsLogRados = true;
    rgwLogObjectNameUtc = true;
    rgwMimeTypesFile = "${pkgs.mailcap}/etc/mime.types";
    debugRados = "1 5";
    rgwFrontends = "beast port=80";
    debugRgw = "1 5";
    rgwLogHttpHeaders = "http_x_forwarded_for,http_x_real_ip";
  };
in
{
  options = {
    flyingcircus.roles.ceph_rgw = {

      enable = lib.mkEnableOption "CEPH Rados Gateway";
      supportsContainers = fclib.mkDisableDevhostSupport;

      primary = lib.mkOption {
        defaultText = "false";
        default = (first_rgw == config.networking.hostName);
        description = "Primary monitors take over additional maintenance tasks.";
        type = lib.types.bool;
      };

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
          config section of the Ceph config file of the radosgw client user.
          Can override existing default setting values. Configuration keys like `mon osd full ratio`''
        + ''
          can alternatively be written in camelCase as `monOsdFullRatio`.
        '';
      };

      cephRelease = fclib.ceph.releaseOption // {
        description = "Codename of the Ceph release series used for the the rgw package.";
      };

      enableAccounting = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether or not to enable traffic accounting.
        '';
      };
      rgwInterface = lib.mkOption {
        internal = true; # only for customising that interface for development
        default = "sto";
        type = lib.types.str;
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf role.enable {

      flyingcircus.services.ceph = {
        fc-ceph.settings.RgwUserManager = {
          release = role.cephRelease;
          path = cephPkgs.fc-ceph-path;
        };
        server = {
          enable = true;
          cephRelease = role.cephRelease;
          # no fc-ceph settings necessary so far
        };

        extraSettingsSections.${username} =
          lib.recursiveUpdate (normaliseCephOptionAttrs defaultRgwSettings) (
            normaliseCephOptionAttrs role.extraSettings
          );
      };

      environment.systemPackages = [ rgw-validate-bucket-names ];

      systemd.tmpfiles.rules = [
        "d /srv/ceph/radosgw 2775 root service"
      ];

      systemd.services.fc-ceph-rgw = rec {
        enable = !config.flyingcircus.services.ceph.server.passive;

        description = "Start/stop local Ceph Rados Gateway";
        wantedBy = [ "multi-user.target" ];
        wants = [ fclib.network."${role.rgwInterface}".addressUnit ];
        requires = [ "network-online.target" ]; # PL-133952
        after = wants ++ requires;

        environment = {
          PYTHONUNBUFFERED = "1";
        };

        restartIfChanged = true;
        restartTriggers = [ config.environment.etc."ceph/ceph.conf".source ];

        serviceConfig = {
          Type = "simple";
          Restart = "always";
          ExecStart = "${cephPkgs.ceph}/bin/radosgw -n ${username} -f -c /etc/ceph/ceph.conf";
        };
      };

      flyingcircus.agent.maintenance.rgw = {
        enter = "fc-ceph maintenance lock .radosgw && systemctl stop fc-ceph-rgw";
        leave = "systemctl start fc-ceph-rgw && fc-ceph maintenance unlock .radosgw";
      };

      networking.firewall.extraStopCommands = ''
        ip46tables -w -t nat -D PREROUTING -j fc-nat-pre 2>/dev/null|| true
        ip46tables -w -t nat -F fc-nat-pre 2>/dev/null || true
        ip46tables -w -t nat -X fc-nat-pre 2>/dev/null || true
      '';

      networking.firewall.extraCommands =
        let
          srv = fclib.network.srv;
          sto = fclib.network."${role.rgwInterface}";
        in
        lib.mkMerge [
          (lib.mkOrder 700 ''
            # Ensure that conntrack is enabled for RGW connections using port redirects
            ip46tables -w -t raw -A fc-raw-prerouting -i ${sto.interface} -p tcp --dport 7480 -j RETURN
            ip46tables -w -t raw -A fc-raw-output -o ${sto.interface} -p tcp --sport 80 -j RETURN
          '')
          (
            ''
              set -x
              # Accept traffic from S3 gateways from within the SRV network.
              ip46tables -w -t nat -N fc-nat-pre

            ''
            + (lib.concatMapStringsSep "\n" (net: ''
              iptables -A nixos-fw -i ${srv.interface} -s ${net} -p tcp --dport 80 -j ACCEPT
              # PL-130368 Fix S3 presigned URLs
              iptables -t nat -A fc-nat-pre -p tcp --dport 7480 -j REDIRECT --to-port 80
            '') srv.v4.networks)
            + "\n"
            + (lib.concatMapStringsSep "\n" (net: ''
              ip6tables -A nixos-fw -i ${srv.interface} -s ${net} -p tcp --dport 80 -j ACCEPT
              # PL-130368 Fix S3 presigned URLs
              ip6tables -t nat -A fc-nat-pre -p tcp --dport 7480 -j REDIRECT --to-port 80
            '') srv.v6.networks)
            + ''
              ip46tables -t nat -A PREROUTING -j fc-nat-pre
            ''
          )
        ];

      systemd.services.fc-ceph-rgw-update-stats = rec {
        description = "Update RGW stats";
        serviceConfig.Type = "oneshot";
        path = [
          cephPkgs.ceph
          pkgs.jq
        ];
        wants = [ fclib.network."${role.rgwInterface}".addressUnit ];
        after = wants;
        script = ''
          for uid in $(radosgw-admin metadata list user | jq -r '.[]'); do
            echo $uid
            radosgw-admin user stats --uid  $uid --sync-stats
          done
        '';
      };

      systemd.services.fc-ceph-account-s3-traffic = {
        description = "accounting for S3 traffic";
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "fc-ceph-s3-accounting";
          ExecStart = "${cephPkgs.fc-ceph}/bin/fc-ceph logs account-s3-traffic -s %S/fc-ceph-s3-accounting/s3-accounting-state";
        };
      };

      systemd.services.fc-ceph-gc-s3-traffic-data = {
        description = "accounting for S3 traffic";
        after = [ "fc-ceph-account-s3-traffic.service" ];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "fc-ceph-s3-accounting";
          ExecStart = "${cephPkgs.fc-ceph}/bin/fc-ceph logs gc-s3-traffic-data -s %S/fc-ceph-s3-accounting/s3-accounting-state";
        };
      };

      systemd.services.fc-ceph-rgw-users = rec {
        description = "Sync S3 users and accounting with directory";
        path = [ cephPkgs.ceph ];
        serviceConfig = {
          Type = "oneshot";
          # The unit gets run every 10 minutes, so stop the unit after 9 minutes runtime
          # This protects against not terminating radosgw-admin calls.
          TimeoutStartSec = 9 * 60;
        };
        wants = [ fclib.network."${role.rgwInterface}".addressUnit ];
        after = wants;
        script = "${cephPkgs.fc-ceph}/bin/fc-s3users --enc ${config.flyingcircus.encPath}";
      };

      flyingcircus.services.sensu-client.checks = {
        radosgw_probe_object = {
          notification = "Probe object (/rgw-monitoring/probe) not OK.";
          command = "check_http -u /rgw-monitoring/probe -H localhost -m 1000000:1500000 -w 5 -c 10";
        };
      };

      services.logrotate.settings.ceph-rgw = {
        files = [ "/var/log/ceph/client.radosgw.log" ];
        create = "0644 root adm";
        postrotate = ''
          systemctl kill -s SIGHUP fc-ceph-rgw
        '';
      };

    })

    (lib.mkIf (role.enable && role.primary) {

      systemd.timers.fc-ceph-account-s3-traffic = {
        enable = !config.flyingcircus.services.ceph.server.passive && role.enableAccounting;

        description = "Timer for accounting S3/object-store traffic";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* *:05:00";
        };
      };

      systemd.timers.fc-ceph-gc-s3-traffic-data = {
        enable = !config.flyingcircus.services.ceph.server.passive && role.enableAccounting;

        description = "Timer for GCing old object-store log data";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 14:30:00";
        };
      };

      systemd.timers.fc-ceph-rgw-update-stats = {
        enable = !config.flyingcircus.services.ceph.server.passive;

        description = "Timer for updating RGW stats";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "10m";
          OnUnitActiveSec = "10m";
        };
      };

      systemd.timers.fc-ceph-rgw-users = {
        enable = !config.flyingcircus.services.ceph.server.passive;

        description = "Timer for syncing S3 users and accounting with the directory";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          Persistent = true;
          OnCalendar = "*:2/10";
        };
      };

      systemd.tmpfiles.rules = [
        "f /var/log/fc-ceph-rgw-users-stamp.log"
      ];

      flyingcircus.services.sensu-client = {
        checks.fc-ceph-rgw-users = {
          notification = "fc-ceph-rgw-users stamp recent";
          command =
            "${pkgs.monitoring-plugins}/bin/check_file_age"
            + " -f /var/log/fc-ceph-rgw-users-stamp.log -w 1500 -c 2700";
          interval = 300;
        };

        checks.fc-ceph-rgw-accounting = {
          notification = "Missing S3 traffic accounting";
          interval = 60;
          command = "${lib.getExe pkgs.python3} ${pkgs.writeText "check-s3-accounting" ''
            import json
            import sys
            from datetime import datetime, timedelta

            with open("/var/lib/fc-ceph-s3-accounting/s3-accounting-state", "r") as f:
                data = json.load(f)

            THRESH_WARN = timedelta(hours=6)
            THRESH_ERR = timedelta(hours=12)

            last_processed = datetime.strptime(data["last_processed_datetime"], "%Y-%m-%dT%H")
            now = datetime.now()

            if now - THRESH_ERR >= last_processed:
                print(f"Last time S3 logs were processed ({last_processed}) is >{THRESH_ERR} ago")
                sys.exit(2)
            elif now - THRESH_WARN >= last_processed:
                print(f"Last time S3 logs were processed ({last_processed}) is >{THRESH_WARN} ago")
                sys.exit(1)
          ''}";
        };
      };

    })

  ];

}
