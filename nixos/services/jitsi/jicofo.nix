{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.jicofo;
in
{
  options.services.jicofo = with types; {
    enable = mkEnableOption "Jitsi Conference Focus - component of Jitsi Meet";

    xmppHost = mkOption {
      type = str;
      example = "localhost";
      description = ''
        Hostname of the XMPP server to connect to.
      '';
    };

    xmppDomain = mkOption {
      type = nullOr str;
      example = "meet.example.org";
      description = ''
        Domain name of the XMMP server to which to connect as a component.

        If null, <option>xmppHost</option> is used.
      '';
    };

    userName = mkOption {
      type = str;
      default = "focus";
      description = ''
        User part of the JID for XMPP user connection.
      '';
    };

    userDomain = mkOption {
      type = str;
      example = "auth.meet.example.org";
      description = ''
        Domain part of the JID for XMPP user connection.
      '';
    };

    userPasswordFile = mkOption {
      type = str;
      example = "/run/keys/jicofo-user";
      description = ''
        Path to file containing password for XMPP user connection.
      '';
    };

    bridgeMuc = mkOption {
      type = str;
      example = "jvbbrewery@internal.meet.example.org";
      description = ''
        JID of the internal MUC used to communicate with Videobridges.
      '';
    };

    config = mkOption {
      type = attrsOf str;
      default = { };
      example = literalExample ''
        {
          "org.jitsi.jicofo.auth.URL" = "XMPP:jitsi-meet.example.com";
        }
      '';
      description = ''
        Contents of the <filename>sip-communicator.properties</filename> configuration file for jicofo.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.jicofo.config = mapAttrs (_: v: mkDefault v) {
      "org.jitsi.jicofo.BRIDGE_MUC" = cfg.bridgeMuc;
    };

    users.groups.jitsi-meet = {};

    systemd.services.jicofo = let
      jicofoProps = {
        "-Dnet.java.sip.communicator.SC_HOME_DIR_LOCATION" = "/etc/jitsi";
        "-Dnet.java.sip.communicator.SC_HOME_DIR_NAME" = "jicofo";
        "-Djava.util.logging.config.file" = "/etc/jitsi/jicofo/logging.properties";
        "-Dconfig.file" = "/etc/jitsi/jicofo/jicofo.conf";
      };
    in
    {
      description = "JItsi COnference FOcus";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      restartTriggers = [
        config.environment.etc."jitsi/jicofo/sip-communicator.properties".source
        config.environment.etc."jitsi/jicofo/jicofo.conf".source
      ];
      environment.JAVA_SYS_PROPS = concatStringsSep " " (mapAttrsToList (k: v: "${k}=${toString v}") jicofoProps);

      stopIfChanged = false;

      script = ''
        watchdog() {
          for count in {1..300}; do
            sleep 1
            ${pkgs.curl}/bin/curl -s http://localhost:8888/about/health && break
            echo "Watchdog: waiting for Jicofo startup, try: $count"
          done

          # Wait before notifying systemd because Jicofo may take a bit longer
          # to be actually ready to talk to a videobridge.
          sleep 5
          echo "Watchdog: Jicofo is ready"
          ${pkgs.systemd}/bin/systemd-notify READY=1

          watchdog_sec=$((WATCHDOG_USEC / 1000000))
          interval=$((watchdog_sec / 2))
          echo "Watchdog: checking every $interval seconds, times out after $watchdog_sec seconds"
          sleep $interval

          while true; do
            echo "Watchdog: check..."
            rc=0
            out=$(${pkgs.curl}/bin/curl --max-time 3 --fail-with-body -s http://localhost:8888/about/health) || rc=$?
            # No need to restart Jicofo when only the videobridge failed ("No operational bridges...")
            if [[ $rc != 0 && $out != "No operational bridges"* ]]; then
              echo "Watchdog: check failed with exit code $rc. Checking again..."
              echo "Watchdog: check output: $out"
              sleep 1
            else
              echo "Watchdog: ok"
              ${pkgs.systemd}/bin/systemd-notify WATCHDOG=1
              sleep $interval
            fi
          done
        }

        watchdog $$ &

        export JICOFO_AUTH_PASSWORD=$(cat ${cfg.userPasswordFile})
        ${pkgs.jicofo}/bin/jicofo
      '';

      serviceConfig = {
        Type = "notify";

        DynamicUser = true;
        User = "jicofo";
        Group = "jitsi-meet";
        WatchdogSec = 40;
        WatchdogSignal = "SIGTERM";
        Restart = "always";

        CapabilityBoundingSet = "";
        NotifyAccess = "all";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectHostname = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
      };
    };

    environment.etc."jitsi/jicofo/jicofo.conf".source =
      pkgs.writeText "jicofo.conf" ''
      jicofo {
        health {
          enabled = true
        }
        xmpp {
          client {
            client-proxy: focus.${cfg.xmppDomain}
            domain: ${cfg.userDomain}
            xmpp-domain: ${if cfg.xmppDomain == null then cfg.xmppHost else cfg.xmppDomain}
            username: ${cfg.userName}
            # The password is set via an environment var in the start script.
            password: ''${JICOFO_AUTH_PASSWORD}
          }
        }
      }
      '';

    flyingcircus.services.sensu-client.checks = {
      jitsi-jicofo-alive = {
        notification = "Jitsi jicofo not healthy";
        command = "check_http -v -H localhost -p 8888 -u /about/health";
      };
    };

    environment.etc."jitsi/jicofo/sip-communicator.properties".source =
      pkgs.writeText "sip-communicator.properties" (
        generators.toKeyValue {} cfg.config
      );
    environment.etc."jitsi/jicofo/logging.properties".source =
      mkDefault "${pkgs.jicofo}/etc/jitsi/jicofo/logging.properties-journal";
  };

  meta.maintainers = lib.teams.jitsi.members;
}
