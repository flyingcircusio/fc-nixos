{ config, lib, pkgs, ... }:

with builtins;
let
  fclib = config.fclib;
in
{
  options =
  let
    mkRole = v: {
      enable = lib.mkEnableOption
        "Enable the Flying Circus RabbitMQ ${v} server role.";
    };
  in {
    flyingcircus.roles = {
      rabbitmq36_5 = {
        enable = lib.mkEnableOption
          "Enable the Flying Circus RabbitMQ 3.6.5 server role (only for upgrades from 20.09).";
        supportsContainers = fclib.mkDisableContainerSupport;
      };

      rabbitmq = {
        enable = lib.mkEnableOption
          "Enable the Flying Circus RabbitMQ server role.";
        supportsContainers = fclib.mkEnableContainerSupport;
      };
    };
  };

  config =
  let
    roles = config.flyingcircus.roles;
    fclib = config.fclib;

    rabbitRoles = with config.flyingcircus.roles; {
      "3.6.5" = rabbitmq36_5.enable;
      "3.12" = rabbitmq.enable;
    };
    enabledRoles = lib.filterAttrs (n: v: v) rabbitRoles;
    enabledRolesCount = length (lib.attrNames enabledRoles);
    enabled = enabledRolesCount > 0;
    roleVersion = head (lib.attrNames enabledRoles);
  in
  lib.mkMerge [

    (lib.mkIf (config.flyingcircus.roles.rabbitmq36_5.enable) {
      flyingcircus.services.rabbitmq365Frozen.enable = true;
    })

    (lib.mkIf (config.flyingcircus.roles.rabbitmq.enable) {
      flyingcircus.services.rabbitmq.enable = true;
    })

    (lib.mkIf enabled {
      assertions =
        [
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
          groups = [ "sudo-srv" "service" ];
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
