{ lib, ... }:

with lib;

{
  debugLog = {
    path = mkOption {
      type = types.str;
      default = "/tmp/debug.log";
    };
    level = mkOption {
      type = types.ints.positive;
      default = 3;
    };
  };
  audit = {
    engine = mkOption {
      type = (
        types.enum [
          "On"
          "Off"
          "RelevantOnly"
        ]
      );
      default = "RelevantOnly";
    };
    # Logrotate for "/var/log/nginx/modsec_*.log" is already configured
    log = {
      format = mkOption {
        type = (
          types.enum [
            "JSON"
            "Native"
          ]
        );
        default = "Native";
      };
      parts = mkOption {
        type = types.str;
        default = "ABIJDFHZ";
      };
      path = mkOption {
        type = types.str;
        default = "/var/log/nginx/modsec_audit.log";
      };
      type = mkOption {
        type = (
          types.enum [
            "Serial"
            "Concurrent"
            "HTTPS"
          ]
        );
        default = "Serial";
      };
    };
  };
  requestBody = {
    access = mkOption {
      type = types.bool;
      default = true;
    };
  };
  collectionTimeout = mkOption {
    type = types.ints.positive;
    default = 600;
  };
  extraConfig = mkOption {
    type = types.lines;
    default = "";
    description = ''
      Rules to append to the config module file verbatim.
    '';
  };
  coreRuleSet = {
    enable = mkEnableOption "OWASP Core Rule Set";
    blocking = mkOption {
      type = types.bool;
      default = false;
    };
    anomalyThreshold = {
      inbound = mkOption {
        type = types.ints.positive;
        default = 5;
      };
      outbound = mkOption {
        type = types.ints.positive;
        default = 4;
      };
    };
  };
}
