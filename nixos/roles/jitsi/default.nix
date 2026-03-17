{
  config,
  pkgs,
  lib,
  ...
}:

with builtins;

let

  fclib = config.fclib;
  cfg = config.flyingcircus.roles.jitsi;

  turnSecretFile = "/etc/local/jitsi/turn-secret";
  turnHostName = if cfg.coturn.enable then cfg.coturn.hostName else cfg.turnHostName;

  # Does the same on the backend side but UI buttons can be turned on/off seperately.
  enableJibri = cfg.enableRecording || cfg.enableLivestreaming;

in
{

  options = with lib; {
    flyingcircus.roles.jitsi = {

      enable = mkEnableOption "Enable a Jitsi Meet server with all needed services.";
      supportsContainers = fclib.mkDisableDevhostSupport;

      coturn = mkOption {
        default = { };
        type = types.submodule {
          options = {
            enable = mkEnableOption ''
              Enable a local coturn preconfigured for Jitsi
              Machines with Jitsi and a local coturn need two public IP addresses.
            '';

            listenAddress = mkOption {
              type = types.str;
              description = ''
                Specify here which IPv4 address to use for coturn.";
              '';
            };

            listenAddress6 = mkOption {
              type = types.str;
              description = ''
                Specify here which IPv6 address to use for coturn.";
              '';
            };

            hostName = mkOption {
              type = types.str;
            };
          };
        };
      };

      enablePublicUDP = mkOption {
        description = "Allow public access to the videobridge via UDP 10000";
        type = types.bool;
        default = true;
      };

      enableRecording = mkOption {
        description = ''
          Enable integration for recording and show the recording button in the UI.
          Needs a separate Jibri installation which is not part of this role.
        '';
        type = types.bool;
        default = false;
      };

      enableLivestreaming = mkOption {
        description = ''
          Enable integration for recording and show the livestream button in the UI.
          Needs a separate Jibri installation which is not part of this role.

          Note: currently live streaming doesn't work, please contact us if you need this feature.
        '';
        type = types.bool;
        default = false;
      };

      enablePrejoinPage = mkOption {
        description = ''
          Shows a page after opening a conference where users can change
          settings and enter their name before joining the conference.
        '';
        type = types.bool;
        default = false;
      };

      enableRoomAuthentication = mkOption {
        description = ''
          Require a username and password to create new rooms.
          Guests can join after the room is created
        '';
        type = types.bool;
        default = false;
      };

      listenAddress = mkOption {
        type = types.str;
        description = ''
          IPv4 address to use for Jitsi.
        '';
      };

      listenAddress6 = mkOption {
        type = types.str;
        description = ''
          IPv6 address to use for Jitsi.
        '';
      };

      hostName = mkOption {
        type = types.str;
      };

      turnHostName = mkOption {
        type = with types; nullOr str;
        default = null;
        description = ''
          Only needed for an external TURN server.
        '';
      };

      maxVideoSenders = mkOption {
        type = with types; types.int;
        default = 8;
        description = ''
          Determines the numbers of clients that can send video streams at the same time.
          If more clients want to send, only the last N speakers are sent and others are muted.
          Jitsi calls the setting 'channelLastN'.
        '';
      };

      resolution = mkOption {
        type = types.int;
        default = 720;
      };

      defaultLanguage = mkOption {
        type = types.str;
        default = "de";
      };

    };

  };

  config = lib.mkMerge [

    (lib.mkIf cfg.enable {

      environment.etc."local/jitsi/README.txt".text = ''
        To customize the content on the welcome page, add a file called welcomePageAdditionalContent.html here.

        You can set a static auth secret for TURN in a file called turn-secret.
        If the file is missing, a random secret is generated on rebuild.
      '';

      environment.systemPackages = with pkgs; [
        (writeScriptBin "jitsi-jvb-show-config" ''
          cat $(systemctl cat jitsi-videobridge | grep JAVA_SYS_PROPS | cut -d= -f4 | cut -d" " -f1)
        '')

        (writeScriptBin "jitsi-jicofo-show-config" ''
          cat /etc/jitsi/jicofo/sip-communicator.properties
        '')

        (writeScriptBin "jitsi-webclient-show-config" ''
          cat $(nginx-show-config | grep '\-config.js' | cut -d' ' -f 2 | tr -d ';')
          cat $(nginx-show-config | grep '\-interfaceConfig.js' | cut -d' ' -f 2 | tr -d ';')
        '')

        (writeScriptBin "jitsi-prosody-show-config" ''
          cat /etc/prosody/prosody.cfg.lua
        '')
      ];

      flyingcircus.localConfigDirs.jitsi = {
        dir = "/etc/local/jitsi";
      };

      flyingcircus.roles.nginx.enable = true;

      flyingcircus.services.telegraf.inputs.http = [
        {
          urls = [ "http://127.0.0.1:8080/colibri/stats" ];
          tagexclude = [ "url" ];
          name_override = "jitsi_jvb";
          data_format = "json";
          fielddrop = [
            "p2p_conferences"
            "version"
          ];
          json_time_key = "current_timestamp";
          json_time_format = "2006-01-02 15:04:05.000";
          json_timezone = "UTC";
        }
      ];

      flyingcircus.services.sensu-client.checks = {
        jitsi-videobridge-alive = {
          notification = "Jitsi videobridge not healthy";
          command = "check_http -v -H localhost -p 8080 -u /about/health";
        };
      };

      networking.firewall.allowedUDPPorts = [ 3478 ] ++ lib.optional cfg.enablePublicUDP 10000;
      networking.firewall.allowedTCPPorts = [ 3478 ];

      services.jitsi-meet = {
        enable = true;
        nginx.enable = true;
        jibri.enable = enableJibri;
        jicofo.enable = true;
        videobridge.enable = true;
        prosody.enable = true;

        secureDomain.enable = cfg.enableRoomAuthentication;
        hostName = cfg.hostName;
        config = {
          channelLastN = cfg.maxVideoSenders;
          constraints = {
            video = {
              height = {
                ideal = cfg.resolution;
                max = cfg.resolution;
                min = 144;
              };
            };
          };
          enableTcc = true;
          enableRemb = true;
          minHDHeight = 540;
          startBitrate = "800";
          disableSimulcast = false;
          defaultLanguage = cfg.defaultLanguage;
          enableLipSync = false;
          enableAutomaticUrlCopy = true;
          enableLayerSuspension = true;
          openBridgeChannel = "websocket";
          prejoinPageEnabled = cfg.enablePrejoinPage;
          useNewBandwidthAllocationStrategy = true;
          desktopSharingFrameRate = {
            min = 5;
            max = 10;
          };
          videoQuality = {
            preferredCodec = "VP9";
          };
          p2p.enabled = false;
          inherit (cfg) resolution;
          startVideoMuted = 8;
          stunServers = [ ];
          recordingService.enabled = cfg.enableRecording;
          # Live streaming currently is broken
          liveStreaming.enabled = cfg.enableLivestreaming;
        }
        // lib.optionalAttrs cfg.enableRoomAuthentication {
          hosts.anonymousdomain = "guest.${cfg.hostName}";
        }
        // lib.optionalAttrs enableJibri {
          hiddenDomain = "recorder.${cfg.hostName}";
        };

        interfaceConfig = {
          DISABLE_VIDEO_BACKGROUND = true;
          DISPLAY_WELCOME_PAGE_CONTENT = true;
          MOBILE_APP_PROMO = false;
          SHOW_JITSI_WATERMARK = false;
          SHOW_WATERMARK_FOR_GUESTS = false;
        };
      };

      services.nginx.virtualHosts = {
        "${cfg.hostName}" = {
          listenAddresses = [
            cfg.listenAddress
            (fclib.quoteIPv6Address cfg.listenAddress6)
          ];
        };
      };

      systemd.services.prosody-coturn-setup-secret = {
        before = [
          "prosody.service"
          "jitsi-meet-init-secrets.service"
        ];
        wantedBy = [
          "prosody.service"
          "jitsi-meet-init-secrets.service"
        ];
        path = [ pkgs.apg ];
        unitConfig.ConditionFileNotEmpty = "!${turnSecretFile}";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
          ProtectSystem = "strict";
          ReadWritePaths = [ "/etc/local/jitsi" ];
          WorkingDirectory = "/etc/local/jitsi";
          ExecStart = "${pkgs.writeShellScript "generate-turn-secret" ''
            apg -a 1 -M lnc -n 1 -m 32 > turn-secret
          ''}";
        };
      };

      systemd.services.prosody = {
        serviceConfig = {
          LoadCredential = [ "turncredentials_secret:${turnSecretFile}" ];
        };
      };

      services.prosody = {
        extraModules = [
          "pinger"
          "turncredentials"
        ];
        extraPluginPaths = [
          ./prosody-plugins
        ];

        extraConfig = ''
          archive_expires_after = "10s";
        ''
        + (lib.optionalString cfg.coturn.enable ''
          -- `prosodyctl` also reads and executes this config file, but has no
          -- access to systemd credentials when running outside the service
          -- context. But it does not require that secret anyways.
          turncredentials_secret = Credential("turncredentials_secret")
          turncredentials = {
            { type = "turn",
              host = "${turnHostName}",
              port = "3478",
              transport = "tcp"
            },
            { type = "turn",
              host = "${turnHostName}",
              port = "443",
              transport = "tcp"
            },
            { type = "turns",
              host = "${turnHostName}",
              port = "443",
              transport = "tcp"
            }
          }
        '');

        virtualHosts = lib.optionalAttrs cfg.enableRoomAuthentication {
          # Force authentication on default vhost which is used for room creation.
          "${cfg.hostName}" = {
            extraConfig = lib.mkForce ''
              authentication = "internal_hashed"
              c2s_require_encryption = false
              admins = { "focus@auth.${cfg.hostName}" }
            '';
          };

          # Define new vhost for anonymous guests in rooms.
          "guest.${cfg.hostName}" = {
            domain = "guest.${cfg.hostName}";
            enabled = true;
            extraConfig = ''
              smacks_max_unacked_stanzas = 5;
              smacks_hibernation_time = 60;
              smacks_max_hibernated_sessions = 1;
              smacks_max_old_sessions = 1;
            '';
          };
        };
      };

      services.jitsi-videobridge = {
        config = {
          videobridge = {
            http-servers = {
              private = {
                host = "127.0.0.1";
                port = 8080;
              };
              public = {
                host = "127.0.0.1";
                port = 9090;
              };
            };

            websockets = {
              enabled = true;
              tls = true;
              server-id = "jvb1";
              domain = "${cfg.hostName}:443";
            };
          };
        };

        extraProperties = lib.optionalAttrs (!cfg.enablePublicUDP) {
          "org.ice4j.ice.harvest.ALLOWED_ADDRESSES" = lib.concatStringsSep ";" (
            fclib.network.srv.dualstack.addresses
          );
        };
      };

      # improve stability of jicofo + videobridge
      # todo: upstream
      #
      services.jicofo.config.jicofo.health.enabled = true;

      systemd.services.jitsi-videobridge2 =
        let
          toVarName =
            s:
            "XMPP_PASSWORD_"
            + lib.stringAsChars (c: if builtins.match "[A-Za-z0-9]" c != null then c else "_") s;
        in
        {
          serviceConfig = {
            Type = fclib.mkOverrideUpstreamModule "notify";
            WatchdogSec = 40;
            WatchdogSignal = "SIGTERM";
            Restart = "always";
            NotifyAccess = "all";
          };
          script = fclib.mkOverrideUpstreamModule (
            (lib.concatStrings (
              lib.mapAttrsToList (name: xmppConfig: ''
                ${toVarName name}=$(cat ${xmppConfig.passwordFile})
                export ${toVarName name}
              '') config.services.jitsi-videobridge.xmppConfigs
            ))
            + ''
              watchdog() {
                # Jicofo takes some seconds to see that the videobridge is not
                # operational. Wait a bit before asking Jicofo about our status.
                sleep 5
                for count in {1..300}; do
                  sleep 1
                  out=$(${pkgs.curl}/bin/curl -s http://localhost:8888/about/health)
                  if [[ $out != *"No operational bridges"* ]]; then
                    break
                  fi
                  echo "Watchdog: waiting until Jicofo sees the videobridge, try: $count"
                done

                echo "Watchdog: videobridge is ready"
                ${pkgs.systemd}/bin/systemd-notify READY=1

                watchdog_sec=$((WATCHDOG_USEC / 1000000))
                interval=$((watchdog_sec / 2))
                echo "Watchdog: checking every $interval seconds, times out after $watchdog_sec seconds"
                sleep $interval

                while true; do
                  echo "Watchdog: check..."
                  out=$(${pkgs.curl}/bin/curl --max-time 3 -s http://localhost:8888/about/health)
                  if [[ $out == *"No operational bridges"* ]]; then
                    echo "Watchdog: check failed, Jicofo does not see the videobridge. Checking again..."
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

              echo "Starting videobridge"

              ${pkgs.jitsi-videobridge}/bin/jitsi-videobridge
            ''
          );
        };

      systemd.services.jicofo = {
        after = [ "prosody.service" ];
        stopIfChanged = false;
      };

    })

    (lib.mkIf (cfg.enable && cfg.coturn.enable) {

      flyingcircus.roles.coturn = {
        enable = true;
        hostName = cfg.coturn.hostName;
      };

      systemd.services.prosody-coturn-setup-secret = {
        before = [ "coturn.service" ];
        wantedBy = [ "coturn.service" ];
      };

      systemd.services.coturn.serviceConfig.LoadCredential = [
        "static-auth-secret:${turnSecretFile}"
      ];

      services.coturn = {
        listening-ips = [
          cfg.coturn.listenAddress
          cfg.coturn.listenAddress6
        ];
        no-tcp = false;
        static-auth-secret-file = "/run/credentials/coturn.service/static-auth-secret";
        tls-listening-port = 443;
        # We don't use it currently, so we can also disable it
        extraConfig = ''
          no-stun
        '';
      };

    })

  ];
}
