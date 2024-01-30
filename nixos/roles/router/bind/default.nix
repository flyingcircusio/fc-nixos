{ config, pkgs, lib, ... }:

with builtins;

let
  inherit (config) fclib;
  role = config.flyingcircus.roles.router;
  inherit (config.flyingcircus) location;
  nameservers = [
    "ns.${location}.gocept.net"
  ];
in
lib.mkIf role.enable {
  environment.etc."bind/pri/127.zone".source = ./127.zone;
  environment.etc."bind/pri/gocept.net-internal.zone.static".source = ./gocept.net-internal.zone.static;
  environment.etc."bind/pri/gocept.net.zone.static".source = ./gocept.net.zone.static;
  environment.etc."bind/pri/1.0.1.0.8.4.2.0.2.0.a.2.zone".source = ./1.0.1.0.8.4.2.0.2.0.a.2.zone;

  environment.etc."local/configure-zones.cfg".text = ''
    [settings]
    pridir = /etc/bind/pri
    ttl = 7200
    suffix = gocept.net
    nameservers = ${lib.concatStringsSep ", " nameservers};
    # XXX: prob not needed
    #reload = /etc/init.d/named reload

    [external]
    zonelist = /etc/bind/external-zones.conf
    include = /etc/bind/pri/gocept.net.zone.static

    [internal]
    zonelist = /etc/bind/internal-zones.conf
    include = /etc/bind/pri/gocept.net.zone.static, /etc/bind/pri/gocept.net-internal.zone.static

    # The list of top-level net allocations must include all configured networks in
    # the directory.
    [zones]
    84.46.96.224/29 = 224-29.96.46.84.in-addr.arpa
    84.46.73.32/27 = 32-27.73.46.84.in-addr.arpa
    84.46.82.0/27 = 0-27.82.46.84.in-addr.arpa
    195.62.117.128/29 = 128-29.117.62.195.in-addr.arpa
    172.16.0.0/16 =
    172.20.0.0/16 =
    172.21.0.0/16 =
    172.22.0.0/16 =
    172.24.0.0/16 =
    172.26.0.0/16 =
    172.30.0.0/16 =
    185.105.252.0/24 =
    185.105.253.0/24 =
    185.105.254.0/24 =
    185.105.255.0/24 =
    192.168.0.0/16 =
    195.62.101.156/30 =
    195.62.111.64/26 =
    195.62.125.0/24 =
    195.62.126.0/24 =
    212.122.41.128/25 = 128-25.41.122.212.in-addr.arpa
    217.69.228.136/30 = 136-30.228.69.217.in-addr.arpa
    2a02:238:1:f030::/48 =
    2a02:238:f030:102::/48 =
    2a02:248:0:1033::/64 =
    2a02:248:101::/48 =
    2a02:248:104::/48 =
    2a02:2028:1007:8000::/56 =
    2a02:2028:ff00::2:8:0/112 =
    2a02:248:0:1032::/125 =
  '';
  networking.resolvconf.useLocalResolver = false;
  services.bind = {
    enable = true;
  };
}
