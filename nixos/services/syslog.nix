{ pkgs, lib, config, ... }:
with builtins;
let
  cfg = config.flyingcircus.syslog;
  fclib = config.fclib;
in
{
  options.flyingcircus.syslog = with lib; {

    separateFacilities = mkOption {
      default = {};
      example = {
        local2 = "/var/log/haproxy.log";
      };
      description = ''
        Configure syslog rules which direct named log facility directly
        into a separate log file.
      '';
      type = types.attrs;
    };

    extraRules = mkOption {
      default = "";
      example = ''
        *.* @graylog.example.org:514
      '';
      description = "custom extra rules for syslog";
      type = types.lines;
    };

  };

  config = let
    extraRules = cfg.extraRules;
    separateFacilities = lib.concatStrings (lib.mapAttrsToList
      (facility: file: "${facility}.info -${file}\n")
      cfg.separateFacilities);
    extraLogFiles = lib.concatStringsSep " " (attrValues cfg.separateFacilities);

  in lib.mkMerge [

    {
      services.rsyslogd.enable =
        fclib.mkPlatform (cfg.extraRules != "" || cfg.separateFacilities != {});

      # fall-back clean rule for "forgotten" logs
      systemd.tmpfiles.rules = [
        "d /var/log 0755 root root 180d"
      ];
    }

    (lib.mkIf config.services.rsyslogd.enable {

      services.rsyslogd = {

        defaultConfig = ''
          $AbortOnUncleanConfig on

          # Reduce repeating messages (default off)
          $RepeatedMsgReduction on

          # Carry complete tracebacks etc.: large messages and don't escape newlines
          $DropTrailingLFOnReception off
          $EscapeControlCharactersOnReceive off
          $MaxMessageSize 64k
          $SpaceLFOnReceive on

          # Inject "--MARK--" messages every $Interval (seconds)
          module(load="immark" Interval="600")

          # Read syslog messages from UDP
          module(load="imudp")
          input(type="imudp" address="127.0.0.1" port="514")
          input(type="imudp" address="::1" port="514")
        '';

        extraConfig =
          let
            exclude = lib.concatMapStrings
              (facility: ";${facility}.none")
              (attrNames cfg.separateFacilities);
          in ''
            *.info${exclude} -/var/log/messages
            ${extraRules}
            ${separateFacilities}
          '';
      };

      services.logrotate.config = ''
        /var/log/messages /var/log/lastlog /var/log/wtmp ${extraLogFiles}
        {
          postrotate
            if [[ -f /run/rsyslogd.pid ]]; then
              ${pkgs.systemd}/bin/systemctl kill --signal=HUP syslog
            fi
          endscript
        }
      '';

      # keep syslog running during system configurations
      systemd.services.syslog.stopIfChanged = false;
    })

  ];
}
