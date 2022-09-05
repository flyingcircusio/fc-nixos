{ pkgs, lib, config, ... }:

with builtins;

let
  cfg = config.flyingcircus.syslog;
  fclib = config.fclib;
  syslogShowConfig = pkgs.writeScriptBin "syslog-show-config" ''
    cat $(systemctl cat syslog | grep "ExecStart=" | cut -d" " -f4 | tr -d '"')
  '';

in
{
  options.flyingcircus.syslog = with lib; {

    separateFacilities = mkOption {
      default = {};
      example = {
        local2 = "/var/log/haproxy.log";
      };
      description = ''
        Configure syslog rules which direct the given log facility directly
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

      systemd.tmpfiles.packages = [
        (lib.mkAfter (pkgs.runCommand "systemd-fc-overwrite-log-tmpfiles" {} ''
          mkdir -p $out/lib/tmpfiles.d
          cd $out/lib/tmpfiles.d

          cp -a "${pkgs.systemd}/example/tmpfiles.d/var.conf" .
          # fixes: Duplicate line for path "/var/log", ignoring.
          sed -r "s|.+/var/log .+||g" -i var.conf
        ''))
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

          module(load="omjournal")
        '';

        extraConfig =
          let
            exclude = lib.concatMapStrings
              (facility: ";${facility}.none")
              (attrNames cfg.separateFacilities);
          in ''
            *.info${exclude} action(type="omjournal")
            ${extraRules}
            ${separateFacilities}
          '';
      };

      services.logrotate.settings = lib.optionalAttrs (extraLogFiles != "") {
        "${extraLogFiles}" = {
          postrotate = ''
            if [[ -f /run/rsyslogd.pid ]]; then
              ${pkgs.systemd}/bin/systemctl kill --signal=HUP syslog
            fi
          '';
        };
      };

      # keep syslog running during system configurations
      systemd.services.syslog.stopIfChanged = false;
    })

  ];
}
