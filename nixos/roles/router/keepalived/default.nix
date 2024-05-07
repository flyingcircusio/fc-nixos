{ config, pkgs, lib, ... }:

with builtins;

let
  inherit (config) fclib;
  inherit (config.networking) hostName;
  inherit (config.flyingcircus) location static;
  role = config.flyingcircus.roles.router;
  locationConfig = readFile (./. + "/${location}.conf");
  routerId = "${hostName}.gocept.net";

  checkDefaultRoute4 = fclib.writeShellApplication {
    name = "check-default-route-v4";
    runtimeInputs = with pkgs; [ iproute2 ];
    text = ''
      ip -4 route | grep "''${1:-default}"
    '';
  };

  checkDefaultRoute6 = fclib.writeShellApplication {
    name = "check-default-route-v6";
    runtimeInputs = with pkgs; [ iproute2 ];
    text = ''
      ip -6 route | grep "''${1:-default}"
    '';
  };

  keepalivedConf = pkgs.writeText "keepalived.conf" ''
    global_defs {
      enable_script_security
      config_save_dir /var/lib/keepalived/saved_config
      notification_email { admin+${hostName}@flyingcircus.io }
      notification_email_from admin+${hostName}@flyingcircus.io
      smtp_server mail.gocept.net
      smtp_connect_timeout 30
      router_id ${routerId}
      script_user root
      use_symlink_paths true
    }

    ${locationConfig}
    '';

  requiredInterfaces =
    map (network: fclib.network."${network}".interface)
      static.floatingGatewayNetworks."${location}";

  addressDependencies = map (iface: "network-addresses-${iface}.service") requiredInterfaces;
  deviceDependencies = map (iface: "${iface}-netdev.service") requiredInterfaces;

in
lib.mkIf role.enable {

  environment.etc."keepalived/check-default-route-v4".source = "${checkDefaultRoute4}/bin/check-default-route-v4";
  environment.etc."keepalived/check-default-route-v6".source = "${checkDefaultRoute6}/bin/check-default-route-v6";
  environment.etc."keepalived/fc-keepalived".source = "${pkgs.fc.agent}/bin/fc-keepalived";
  environment.etc."keepalived/keepalived.conf".source = keepalivedConf;

  environment.systemPackages = with pkgs; [
    keepalived
    checkDefaultRoute4
    checkDefaultRoute6
  ];


  flyingcircus.passwordlessSudoRules = [
    {
      commands = [
        "${pkgs.fc.agent}/bin/fc-keepalived check"
      ];
      groups = [ "admins" "sudo-srv" "service" ];
    }
  ];

  services.keepalived = {
    enable = true;
    # Note: We override the keepalived config file in ExecStart below,
    # using config options here has no effect.
  };

  systemd.services.keepalived = {
    reloadIfChanged = true;
    # Don't be confused by the name "restartTriggers", reload also uses it.
    restartTriggers = [ keepalivedConf ];
    # Ensure that keepalived is stopped *before* interfaces are
    # stopped at shutdown.
    after = deviceDependencies;
    serviceConfig = {
      Type = lib.mkOverride 90 "simple";
      ExecStart = lib.mkOverride 90 ("${pkgs.keepalived}/sbin/keepalived"
        + " -f /etc/keepalived/keepalived.conf"
        + " -p /run/keepalived.pid"
        + " -n");
      StateDirectory = "keepalived";
      RuntimeDirectory = "keepalived";
    };
  };

  systemd.services.keepalived-reload = {
    description = "Reload keepalived when required interfaces are changed";
    after = addressDependencies ++ deviceDependencies;
    wantedBy = deviceDependencies;
    serviceConfig = {
      Type = "oneshot";
      Restart = "on-abnormal";
      TimeoutSec = 120;
      ExecCondition = "/run/current-system/systemd/bin/systemctl -q is-active keepalived.service";
      ExecStart = "/run/current-system/systemd/bin/systemctl reload keepalived.service";
    };
  };

  networking.firewall.extraCommands = ''
    ip6tables -A nixos-fw -p 112 -j nixos-fw-accept
  '';

  systemd.tmpfiles.rules = [
    "d /etc/keepalived 0755 root root"
  ];
}
