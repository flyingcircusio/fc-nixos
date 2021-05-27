{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.services.jibri;
  # HOCON is a JSON superset that videobridge2 uses for configuration.
  # It can substitute environment variables which we use for passwords here.
  # https://github.com/lightbend/config/blob/master/README.md
  #
  # Substitution for environment variable FOO is represented as attribute set
  # { __hocon_envvar = "FOO"; }
  toHOCON = x: if isAttrs x && x ? __hocon_envvar then ("\${" + x.__hocon_envvar + "}")
    else if isAttrs x then "{${ lib.concatStringsSep "," (lib.mapAttrsToList (k: v: ''"${k}":${toHOCON v}'') x) }}"
    else if isList x then "[${ lib.concatMapStringsSep "," toHOCON x }]"
    else toJSON x;

  settings = with cfg; {
    jibri = {
      api = {
        xmpp = {
          environments = [{
            name = "prod environment";
            xmpp-server-hosts = ["${xmppDomain}"];
            xmpp-domain = "${xmppDomain}";

            control-muc = {
              domain = "internal.${xmppDomain}";
              room-name = "JibriBrewery";
              nickname = "jibri-nickname";
            };

            control-login = {
              domain = "${controlDomain}";
              username = "${controlUser}";
              password = { __hocon_envvar = "JIBRI_CONTROL_PASSWORD"; };
            };

            call-login = {
              domain = "${recorderDomain}";
              username = "${recorderUser}";
              password = { __hocon_envvar = "JIBRI_RECORDER_PASSWORD"; };
            };

            strip-from-room-domain = "conference.";
            usage-timeout = 0;
            trust-all-xmpp-certs = true;
          }];
        };
      };

      ffmpeg = {
        resolution = "${toString cfg.resolution.width}x${toString cfg.resolution.height}";
      };

      recording = {
        recordings-directory = "/var/lib/jibri";
        finalize-script = "${finalizeScript}";
      };
    };
  };

in
{
  options.services.jibri = with lib; {
    enable = mkEnableOption "Enable Jitsi recording and live streaming with Jibri";

    finalizeScript = mkOption {
      type = types.path;
      default = pkgs.writeScript "jibri-finalize-recording" ''
        #!${pkgs.runtimeShell}
        RECORDINGS_DIR=$1

        echo "This is a dummy finalize script" > /var/lib/jibri/finalize.out
        echo "The script was invoked with recordings directory $RECORDINGS_DIR." >> /var/lib/jibri/finalize.out
        echo "You should put any finalize logic (renaming, uploading to a service" >> /var/lib/jibri/finalize.out
        echo "or storage provider, etc.) in this script" >> /var/lib/jibri/finalize.out

        exit 0
      '';
      description = ''
        Script which is called with the recording's directory after recording has stopped.
      '';
    };

    xmppDomain = mkOption {
      type = with types; nullOr str;
      example = "meet.example.org";
      description = ''
        Domain name of the XMMP server to which to connect as a component.
      '';
    };

    controlUser = mkOption {
      type = types.str;
      default = "jibri";
      description = ''
        User part of the JID for XMPP control connection.
      '';
    };

    recorderUser = mkOption {
      type = types.str;
      default = "recorder";
      description = ''
        User part of the JID for XMPP call (recorder) connection.
      '';
    };

    recorderDomain = mkOption {
      type = types.str;
      example = "recorder.meet.example.org";
      description = ''
        Domain part of the JID for the recorder.
      '';
    };

    resolution = mkOption {
      default = {};
      type = types.submodule {
        options = {
          width = mkOption {
            type = types.int;
            default = 1280;
          };
          height = mkOption {
            type = types.int;
            default = 720;
          };
        };
      };
    };

    controlDomain = mkOption {
      type = types.str;
      example = "auth.meet.example.org";
      description = ''
        Domain part of the JID for control connection.
      '';
    };

    controlPasswordFile = mkOption {
      type = types.str;
      example = "/run/keys/jibri-control";
      description = ''
        Path to file containing the password for the control connection.
      '';
    };

    recorderPasswordFile = mkOption {
      type = types.str;
      example = "/run/keys/jibri-recorder";
      description = ''
        Path to file containing the password for the recorder connection.
      '';
    };

    loggingConfigFile = mkOption {
      type = types.path;
      default = "${pkgs.jibri}/etc/jitsi/jibri/logging.properties-journal";
    };

    configFile = mkOption {
      type = types.path;
      default = "${pkgs.writeText "jibri.conf" (toHOCON cfg.settings)}";
      description = ''
        Jibri main config file path.
        By default, this is set to the auto-generated config which you can override with a custom file path.
      '';
    };

    settings = mkOption {
      type = types.attrs;
      default = settings;
      description = "Settings used to generate the default config file";
    };

  };

  config = lib.mkIf cfg.enable {

    boot.extraModprobeConfig = ''
      options snd-aloop enable=1,1,1,1,1 index=0,1,2,3,4
    '';
    boot.kernelModules = [ "snd-aloop" ];

    sound.enable = true;

    environment.etc."asound.conf".source = "${pkgs.jibri}/etc/jitsi/jibri/asoundrc";

    environment.etc."chromium/policies/managed/managed_policies.json".source =
      pkgs.writeText "managed_policies.json" (
        lib.generators.toJSON {} {
          CommandLineFlagSecurityWarningsEnabled = false;
        }
      );

    systemd.services.jibri-icewm = {
      after = [ "jibri-xorg.service" ];
      requires = [ "jibri-xorg.service" ];
      wantedBy = [ "multi-user.target" ];
      description = "Jibri Window Manager";
      environment = {
        DISPLAY = ":0";
      };

      serviceConfig = {
        ExecStart = ''
          ${pkgs.icewm}/bin/icewm-session
        '';
        User = "jibri";
        Group = "jitsi-meet";
        Restart = "on-failure";

        # Security restrictions, systemd-analyze security score is 3.2
        CapabilityBoundingSet = "";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
      };
    };

    systemd.services.jibri-xorg = {
      description = "Jibri Xorg Process";

      wantedBy = [ "multi-user.target" ];

      environment = {
        DISPLAY = ":0";
      };

      script =
      let
        xorgConf = pkgs.writeText "jitsi-xorg.conf" (pkgs.callPackage
          ./xorg-video-dummy.conf.nix { inherit (cfg) resolution; });
      in ''
        ${pkgs.xorg.xorgserver.out}/bin/Xorg \
          -nocursor -noreset +extension RANDR +extension RENDER \
          -config ${xorgConf} \
          -logfile /var/log/jibri-xorg/xorg.log
          :0
      '';
      serviceConfig = {
        User = "jibri";
        LogsDirectory = "jibri-xorg";
        Group = "jitsi-meet";
        Restart = "on-failure";

        # Security restrictions, systemd-analyze security score is 3.2
        CapabilityBoundingSet = "";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
      };
    };

    systemd.services.jibri = {
      description = "JItsi BRoadcasting Infrastructure";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "jibri-xorg.service" ];
      wants = [ "jibri-icewm.service" ];

      environment = {
        JIBRI_CONFIG_FILE = cfg.configFile;
        JIBRI_LOGGING_CONFIG_FILE = cfg.loggingConfigFile;
      };

      script = ''
        export JIBRI_RECORDER_PASSWORD=$(cat ${cfg.recorderPasswordFile})
        export JIBRI_CONTROL_PASSWORD=$(cat ${cfg.controlPasswordFile})
        ${pkgs.jibri}/bin/jibri
      '';

      serviceConfig = {
        Type = "exec";

        DynamicUser = true;

        LogsDirectory = "jibri";
        StateDirectory = "jibri";

        User = "jibri";
        Group = "jitsi-meet";
        SupplementaryGroups = [
          "audio"
        ];

        # Security restrictions, systemd-analyze security score is 1.6
        CapabilityBoundingSet = "";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@basic-io"
          "@network-io"
        ];
      };
    };

  };

  meta.maintainers = lib.teams.jitsi.members;
}
