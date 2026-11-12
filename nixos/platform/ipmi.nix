{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.flyingcircus;
  fclib = config.fclib;

  ipmi_interface = cfg.enc.parameters.interfaces.ipmi;
  ipmi_v4_network_cidr = head (filter fclib.isIp4 (attrNames ipmi_interface.networks));

  ipmi_addr = head ipmi_interface.networks.${ipmi_v4_network_cidr};
  ipmi_netmask = fclib.netmaskFromCIDR ipmi_v4_network_cidr;
  ipmi_gw = ipmi_interface.gateways.${ipmi_v4_network_cidr};

  # The IPMI device is not necessarily available yet when this unit runs during
  # boot (PL-133838), we do a few retries with exponential backoff to give it
  # time to come up: 5s, 9s, 17s, 32s, 60s between the six attempts.
  ipmi_configure_attempts = 6;
  ipmi_configure_retry_delay = 5;
  ipmi_configure_retry_steps = 4;
  ipmi_configure_retry_max_delay = 60;
  ipmi_configure_attempt_timeout = 30;
  ipmi_configure_retry_window = 360;

in
{

  options = {
    flyingcircus.ipmi = {
      enable = mkOption {
        default = false;
        description = "Manage the IPMI controller.";
        type = types.bool;
      };
      watchdogTimeout = mkOption {
        default = 300;
        description = "Watchdog timeout (0 = off)";
        type = types.int;
      };
      check_additional_options = mkOption {
        default = "";
        description = "Additional options to pass to `check_ipmi_sensor`.";
        type = types.str;
      };
      manageAdminUserName = mkOption {
        default = true;
        description = "Manage the admin user name (setting it to `ADMIN`).";
        type = types.bool;
      };
    };
  };

  config = mkIf cfg.ipmi.enable {

    environment.systemPackages = [
      pkgs.ipmitool
      pkgs.fc.ipmitool
    ];

    boot.blacklistedKernelModules = [ "wdat_wdt" ];
    boot.kernelModules = [ "ipmi_watchdog" ];

    systemd.settings.Manager = {
      RuntimeWatchdogSec = toString cfg.ipmi.watchdogTimeout;
    };

    services.udev.extraRules = ''
      KERNEL=="ipmi[0-9]", GROUP="adm", MODE="0660"
    '';

    systemd.timers.ipmi-log = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1m";
        OnUnitActiveSec = "10m";
      };
    };

    systemd.services.ipmi-log = {
      description = "Export (and clear) the ipmi log.";
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.ipmitool}/bin/ipmitool sel elist
        ${pkgs.ipmitool}/bin/ipmitool sel clear
      '';
    };

    systemd.services.configure-ipmi-controller = {
      description = "Configure IPMI controller";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = ipmi_configure_retry_delay;
        # Does exponential backoff
        RestartSteps = ipmi_configure_retry_steps;
        RestartMaxDelaySec = ipmi_configure_retry_max_delay;
        TimeoutStartSec = ipmi_configure_attempt_timeout;
      };
      startLimitBurst = ipmi_configure_attempts;
      startLimitIntervalSec = ipmi_configure_retry_window;
      path = [ pkgs.ipmitool ];
      wantedBy = [ "basic.target" ];
      script = ''
        ipmitool lan set 1 ipsrc static
        sleep 1
        ipmitool lan set 1 ipaddr ${ipmi_addr}
        sleep 1
        ipmitool lan set 1 netmask ${ipmi_netmask}
        sleep 1
        ipmitool lan set 1 defgw ipaddr ${ipmi_gw}
        sleep 1
        ipmitool sol set non-volatile-bit-rate 115.2 1
        sleep 1
        ipmitool sol set volatile-bit-rate 115.2 1
        sleep 1
      ''
      + (lib.optionalString cfg.ipmi.manageAdminUserName ''
        ipmitool user set name 2 ADMIN
      '')
      + ''
        # See https://serverfault.com/questions/361940/configuring-supermicro-ipmi-to-use-one-of-the-lan-interfaces-instead-of-the-ipmi/677087
        # Ensure BMC is set to failover (SuperMicro only)
        if ipmitool mc info | grep Supermicro > /dev/null ; then
          ipmitool raw 0x30 0x70 0x0c 1 2 || true
        fi
      '';
    };

    flyingcircus.passwordlessSudoPackages = [
      {
        commands = [ "bin/check_ipmi_sensor" ];
        package = pkgs.check_ipmi_sensor;
        groups = [ "sensuclient" ];
      }
    ];

    flyingcircus.services.sensu-client.checks = {
      IPMI-sensors = {
        notification = "IPMI sensors";
        command = "sudo ${pkgs.check_ipmi_sensor}/bin/check_ipmi_sensor --noentityabsent ${cfg.ipmi.check_additional_options}";
      };
    };

  };

}
