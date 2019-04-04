{ lib, ... }:

with lib;
{
  options = {
    flyingcircus.static = mkOption {
      type = with types; attrsOf attrs;
      default = { };
      description = "Static lookup tables for site-specific information";
    };
  };

  config = {
    flyingcircus.static = {

      locations = {
        "whq" = { id = 0; site = "Halle"; };
        "yard" = { id = 1; site = "Halle"; };
        "rzob" = { id = 2; site = "Oberhausen"; };
        "dev" = { id = 3; site = "Halle"; };
        "rzrl1" = { id = 4; site = "Norderstedt"; };
      };

      # Note: this list of VLAN classes should be kept in sync with
      # fc.directory/src/fc/directory/vlan.py
      vlans = {
        # management (grey): BMC, switches, tftp, remote console
        "1" = "mgm";
        # frontend (yellow): access from public Internet
        "2" = "fe";
        # servers/backend (red): RG-internal (app, database, ...)
        "3" = "srv";
        # storage (black): VM storage access (Ceph)
        "4" = "sto";
        # transfer (blue): primary router uplink
        "6" = "tr";
        # storage backend (yellow): Ceph replication and migration
        "8" = "stb";
        # transfer 2 (blue): secondary router-router connection
        "14" = "tr2";
        # gocept office
        "15" = "gocept";
        # frontend (yellow): additional fe needed on some switches
        "16" = "fe2";
        # servers/backend (red): additional srv needed on some switches
        "17" = "srv2";
        # transfer 3 (blue): tertiary router-router connection
        "18" = "tr3";
        # dynamic hardware pool: local endpoints for Kamp DHP tunnels
        "19" = "dhp";
      };

      nameservers = {
        # ns.$location.gocept.net, ns2.$location.gocept.net
        # We are currently not using IPv6 resolvers as we have seen obscure bugs
        # when enabling them, like weird search path confusion that results in
        # arbitrary negative responses, combined with the rotate flag.
        #
        # This seems to be https://sourceware.org/bugzilla/show_bug.cgi?id=13028
        # which is fixed in glibc 2.22 which is included in NixOS 16.03.
        dev = [ "172.20.2.1" "172.20.3.7" "172.20.3.57" ];
        whq = [ "212.122.41.129" "212.122.41.173" "212.122.41.169" ];
        rzob = [ "195.62.125.1" "195.62.126.130" "195.62.126.131" ];
        rzrl1 = [ "84.46.82.1" "172.24.48.2" "172.24.48.10" ];
        standalone = [ "9.9.9.9" "8.8.8.8" ];
      };

      directory = {
        proxy_ips = [
          "195.62.125.11"
          "195.62.125.243"
          "195.62.125.6"
          "2a02:248:101:62::108c"
          "2a02:248:101:62::dd"
          "2a02:248:101:63::d4"
        ];
      };

      firewall = {
        trusted = [
          # vpn-rzob.services.fcio.net
          "172.22.49.56"
          "195.62.126.69"
          "2a02:248:101:62::1187"
          "2a02:248:101:63::118f"

          # vpn-whq.services.fcio.net
          "172.16.48.35"
          "212.122.41.150"
          "2a02:238:f030:102::1043"
          "2a02:238:f030:103::1073"

          # Office
          "213.187.89.32/29"
          "2a02:238:f04e:100::/56"
        ];
      };

      ntpServers = {
        # Those are the routers and backup servers. This needs to move to the
        # directory service discovery.
        dev = [ "selma" "eddie" "sherry" ];
        whq = [ "barbrady01" "terri" "bob" "lou" ];
        rzob = [ "kenny06" "kenny07" "barbrady02" ];
        rzrl1 = [ "kenny02" "kenny03" "barbrady03" ];
      };

      adminKeys = {
        directory = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDSejGFORJ7hlFraV3caVir3rWlo/QcsWptWrukk2C7eaGu/8tXMKgPtBHYdk4DYRi7EcPROllnFVzyVTLS/2buzfIy7XDjn7bwHzlHoBHZ4TbC9auqW3j5oxTDA4s2byP6b46Dh93aEP9griFideU/J00jWeHb27yIWv+3VdstkWTiJwxubspNdDlbcPNHBGOE+HNiAnRWzwyj8D0X5y73MISC3pSSYnXJWz+fI8IRh5LSLYX6oybwGX3Wu+tlrQjyN1i0ONPLxo5/YDrS6IQygR21j+TgLXaX8q8msi04QYdvnOqk1ntbY4fU8411iqoSJgCIG18tOgWTTOcBGcZX directory@directory.fcio.net";
        ctheune = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIrMeeyMUiSfXGnhvdIk50RsW3VMAbmYAChOGmiKGMUc ctheune@thirteen.fritz.box";
        ckauhaus = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB6MKl9D9mzhuB6/sQXNCEW5qq4R7mXlpnxi+QZSGi57 root/ckauhaus@fcio.net";
        zagy = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKqKaOCYLUxtjAs9e3amnTRH5NM2j0kjLOE+5ZGy9/W4 zagy@drrr.local";
        flanitz = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAg5mbkbBk0dngSVmlZJEH0hAUqnu3maJzqEV9Su1Cff flanitz";
        cs = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKIlrvXV9TzM1uppd8oAbph1dcab6h28VZSUthsp2eZL christians@colbert";
      };

    };

    ids.uids = {
      # Our custom services
      sensuserver = 31001;
      sensuapi = 31002;
      uchiwa = 31003;
      sensuclient = 31004;
      powerdns = 31005;
    };

    ids.gids = {
      users = 100;
      # The generic 'service' GID is different from Gentoo.
      # But 101 is already used in NixOS.
      service = 900;

      # Our permissions
      login = 500;
      code = 501;
      stats = 502;
      sudo-srv = 503;
      manager = 504;

      # Our custom services
      sensuserver = 31001;
      sensuapi = 31002;
      uchiwa = 31003;
      sensuclient = 31004;
      powerdns = 31005;
    };

  };
}
