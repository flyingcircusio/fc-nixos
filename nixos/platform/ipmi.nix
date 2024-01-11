{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.flyingcircus;
  fclib = config.fclib;

  ipmi_interface = cfg.enc.parameters.interfaces.ipmi;
  ipmi_v4_network_cidr = head (filter fclib.isIp4 (attrNames ipmi_interface.networks));

  ipmi_addr = head ipmi_interface.networks.${ipmi_v4_network_cidr};
  ipmi_netmask = fclib.netmaskFromCIDR ipmi_v4_network_cidr;
  ipmi_gw = ipmi_interface.gateways.${ipmi_v4_network_cidr};

in {

  options = {
    flyingcircus.ipmi = {
      enable = mkOption {
        default = false;
        description = "Manage the IPMI controller.";
        type = types.bool;
      };
      check_additional_options = mkOption {
        default = "";
        description = "Additional options to pass to `check_ipmi_sensor`.";
        type = types.str;
      };
    };
  };

  config = mkIf cfg.ipmi.enable {

    environment.systemPackages = [ pkgs.ipmitool ];

    boot.blacklistedKernelModules = [ "wdat_wdt" ];
    boot.kernelModules = [ "ipmi_watchdog" ];

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
      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = true;
      wantedBy = [ "basic.target" ];
      script = ''
        ${pkgs.ipmitool}/bin/ipmitool lan set 1 ipsrc static
        sleep 1
        ${pkgs.ipmitool}/bin/ipmitool lan set 1 ipaddr ${ipmi_addr}
        sleep 1
        ${pkgs.ipmitool}/bin/ipmitool lan set 1 netmask ${ipmi_netmask}
        sleep 1
        ${pkgs.ipmitool}/bin/ipmitool lan set 1 defgw ipaddr ${ipmi_gw}
        sleep 1
        ${pkgs.ipmitool}/bin/ipmitool sol set non-volatile-bit-rate 115.2 1
        sleep 1
        ${pkgs.ipmitool}/bin/ipmitool sol set volatile-bit-rate 115.2 1
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
        command = ''
          sudo ${pkgs.check_ipmi_sensor}/bin/check_ipmi_sensor  --noentityabsent ${cfg.ipmi.check_additional_options}
        '';
      };
    };

   };

}
