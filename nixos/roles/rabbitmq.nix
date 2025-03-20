{
  config,
  lib,
  pkgs,
  ...
}:

with builtins;
let
  fclib = config.fclib;
in
{
  options = {
    flyingcircus.roles = {
      rabbitmq36_5 = {
        enable = lib.mkEnableOption "Enable the Flying Circus RabbitMQ 3.6.5 server role (only for upgrades from 20.09).";
        supportsContainers = fclib.mkDisableDevhostSupport;
      };

      rabbitmq = {
        enable = lib.mkEnableOption "Enable the Flying Circus RabbitMQ server role.";
        supportsContainers = fclib.mkEnableDevhostSupport;
      };
    };
  };

  config =
    let
      fclib = config.fclib;

      rabbitRoles = with config.flyingcircus.roles; {
        "3.6.5" = rabbitmq36_5.enable;
        "current" = rabbitmq.enable;
      };
      enabledRoles = lib.filterAttrs (n: v: v) rabbitRoles;
      enabledRolesCount = length (lib.attrNames enabledRoles);
      enabled = enabledRolesCount > 0;
      isSingleNode = length (fclib.findServices "rabbitmq-node") == 1;
    in
    lib.mkMerge [

      (lib.mkIf (config.flyingcircus.roles.rabbitmq36_5.enable) {
        flyingcircus.services.rabbitmq365Frozen.enable = true;
      })

      (lib.mkIf (config.flyingcircus.roles.rabbitmq.enable) {
        flyingcircus.services.rabbitmq.enable = true;
      })

      # For single-node setups of current RabbitMQ versions, set feature flags
      # automatically after platform upgrades. This is the easy and common case.
      # Cluster setups require manual intervention for enabling feature flags.
      # Note that we simply check the number of rabbitmq instances in the RG to be safe,
      # we don't know here if they actually form a cluster.
      (lib.mkIf (config.flyingcircus.roles.rabbitmq.enable && isSingleNode) {
        systemd.services.rabbitmq.postStart = "rabbitmqctl enable_feature_flag all";
      })

      (lib.mkIf enabled {
        assertions = [
          {
            assertion = enabledRolesCount == 1;
            message = "RabbitMQ roles are mutually exclusive. Only one may be enabled.";
          }
        ];

        users.extraUsers.rabbitmq = {
          shell = "/run/current-system/sw/bin/bash";
        };

        flyingcircus.passwordlessSudoRules = [
          # Service users may switch to the rabbitmq system user
          {
            commands = [ "ALL" ];
            groups = [
              "sudo-srv"
              "service"
            ];
            runAs = "rabbitmq";
          }
        ];

      })

      {
        flyingcircus.roles.statshost.prometheusMetricRelabel = [
          {
            regex = "idle_since";
            action = "labeldrop";
          }
        ];
      }
    ];
}
