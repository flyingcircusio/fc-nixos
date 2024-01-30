{ config, pkgs, lib, ... }:

with builtins;

let
  inherit (config) fclib;
  inherit (config.networking) hostName;
  inherit (config.flyingcircus) location;
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

in
lib.mkIf role.enable {
  environment.systemPackages = with pkgs; [
    keepalived
    checkDefaultRoute4
    checkDefaultRoute6
  ];

  services.keepalived = {
    enable = true;
    extraGlobalDefs = ''
       notification_email { admin+${hostName}@flyingcircus.io }
       notification_email_from admin+${hostName}@flyingcircus.io
       smtp_server mail.gocept.net
       smtp_connect_timeout 30
       router_id ${routerId}
       script_user root
       enable_script_security
    '';
    extraConfig = locationConfig;
  };

  systemd.tmpfiles.rules = [
    "d /etc/keepalived 0755 root root"
    "f /etc/keepalived/stop 0644 root root - 0"
  ];
}
