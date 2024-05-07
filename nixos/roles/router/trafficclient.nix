{ config, pkgs, lib, ... }:

with builtins;

let
  inherit (config) fclib;
  inherit (config.flyingcircus) location;
  role = config.flyingcircus.roles.router;
  configFile =
    pkgs.writeText "trafficclient.conf" ''
      [trafficclient]
      dbdir = /var/db/trafficclient
      location = ${location}
      ignored-ips = 2a02:238:f030:102::103b
        212.122.41.135
        46.237.250.54
        80.147.225.83
        2a02:248:0::/48
        195.62.121.0/24
        195.62.122.0/24
        195.62.123.0/24
        195.62.127.0/24
        82.141.39.0/24
    '';
in
lib.mkIf role.enable {
  environment.etc."trafficclient.conf".source = configFile;

  systemd.services.fc-trafficclient = {
    description = "Measure traffic and report it to the traffic server";
    requires = [ "network-online.target" ];
    after = [ "network-online.service" "pmacctd.service" ];
    script = ''
      ${pkgs.fc.trafficclient}/bin/fc-trafficclient ${configFile}
    '';
    serviceConfig = {
      StateDirectory = "trafficclient";
      TimeoutStartSec = "10m";
    };
  };

  systemd.timers.fc-trafficclient = {
    description = "Timer for fc-trafficclient";
    wantedBy = [ "timers.target" ];
    requires = [ "network-online.target" ];
    timerConfig = {
      OnActiveSec = "1m";
      OnUnitInactiveSec = "2m";
    };
  };
}
