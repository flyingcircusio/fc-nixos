{ pkgs, lib, config, ... }:
with builtins;
let
  cfg = config.flyingcircus.syslog;
  fclib = config.fclib;
  syslogShowConfig = pkgs.writeScriptBin "syslog-show-config" ''
    cat $(systemctl cat syslog | grep "ExecStart=" | cut -d" " -f4 | tr -d '"')
  '';

  resourceGroupLoghosts =
    fclib.listServiceAddresses "graylog-server" ++
    fclib.listServiceAddresses "loghost-server";

  logTargets = lib.unique (
    # Pick one of the resource group loghosts or a graylog from the cluster...
    (if (length resourceGroupLoghosts > 0) then
      [(head resourceGroupLoghosts)] else []) ++

    # ... and always add the central location loghost (if it exists).
    (fclib.listServiceAddresses "loghost-location-server"));

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

      environment.systemPackages = [
        syslogShowConfig
      ];

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

      services.logrotate.extraConfig = ''
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

    (lib.mkIf (length logTargets > 0) {
      # Forward all syslog to graylog, if there is one.
      flyingcircus.syslog.extraRules = concatStringsSep "\n"
        (map (target: "*.* @${target}:5140;RSYSLOG_SyslogProtocol23Format") logTargets);
    })

  ];
}
