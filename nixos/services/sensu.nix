{ config, pkgs, lib, ... }:

with lib;

let
  checkOptions = { name, config, ... }: {
    options = {
      notification = mkOption {
        type = types.str;
        description = "The notification on events.";
      };
      command = mkOption {
        type = types.str;
        description = "The command to execute as the check.";
      };
      interval = mkOption {
        type = types.int;
        default = 60;
        description = "The interval (in seconds) how often this check should be performed.";
      };
      timeout = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "The timeout when the client should abort the check and consider it failed.";
      };
      ttl = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "The time after which a check result should be considered stale and cause an event.";
      };
      standalone = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to schedule this check autonomously on the client.";
      };
      warnIsCritical = mkOption {
        type = types.bool;
        default = false;
        description = "Whether a warning of this check should be escalated to critical by our status page.";
      };
    };
  };

in {
  options = {

    flyingcircus.services.sensu-client = {
      enable = mkEnableOption "Sensu monitoring client daemon";
      server = mkOption {
        type = types.str;
        description = ''
          The address of the server (RabbitMQ) to connect to.
        '';
      };
      loglevel = mkOption {
        type = types.str;
        default = "warn";
        description = ''
          The level of logging.
        '';
      };
      password = mkOption {
        type = types.str;
        description = ''
          The password to connect with to server (RabbitMQ).
        '';
      };
      config = mkOption {
        type = types.lines;
        description = ''
          Contents of the sensu client configuration file.
        '';
      };
      checks = mkOption {
        default = {};
        type = types.attrsOf types.optionSet;
        options = [ checkOptions ];
        description = ''
          Checks that should be run by this client.
          Defined as attribute sets that conform to the JSON structure
          defined by Sensu:
          https://sensuapp.org/docs/latest/checks
        '';
      };
      extraOpts = mkOption {
        type = with types; listOf str;
        default = [];
        description = ''
          Extra options used when launching sensu.
        '';
      };
      expectedConnections = {
        warning = mkOption {
          type = types.int;
          description = ''
            Set the warning limit for connections on this host.
          '';
          default = 5000;
        };
        critical = mkOption {
          type = types.int;
          description = ''
            Set the critical limit for connections on this host.
          '';
          default = 6000;
        };
      };
      expectedLoad = {
        warning = mkOption {
          type = types.str;
          default = "${toString (cores * 8)},${toString (cores * 5)},${toString (cores * 2)}";
          description = ''Limit of load thresholds before warning.'';
        };
        critical = mkOption {
          type = types.str;
          default = "${toString (cores * 10)},${toString (cores * 8)},${toString (cores * 3)}";
          description = ''Limit of load thresholds before reaching critical.'';
        };
      };
      expectedSwap = {
        warning = mkOption {
          type = types.str;
          default = "1024";
          description = ''Limit of swap usage in MiB before warning.'';
        };
        critical = mkOption {
          type = types.str;
          default = "2048";
          description = ''Limit of swap usage in MiB before reaching critical.'';
        };
      };
    };
  };

  # XXX implementation missing

}
