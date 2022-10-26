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

      ceph.fsids = {
        # These are needed once per cluster.
        # Generate a new one via: `uuidgen -t` and record
        # it here with the ${location}.${resourcegroup} key
        dev.services = "b67bad36-3273-11e3-a2ed-0200000311bf";
        whq.services = "be45fd6c-ea68-11e2-ad96-0200000311c0";
        rzob.services = "d4b91002-eaf4-11e2-bc7c-0200000311c1";
        rzob.risclog = "1f417812-eafa-11e2-aa4f-0200000311c1";
        rzrl1.risclog = "ad1d2380-81da-11e3-9c5f-0200000311bf";
      };

      # Note: this list of VLAN classes should be kept in sync with
      # fc.directory/src/fc/directory/vlan.py
      vlanIds = {
        # management (grey): BMC, switches, tftp, remote console
        "mgm" = 1;
        # frontend (yellow): access from public Internet
        "fe" = 2;
        # servers/backend (red): RG-internal (app, database, ...)
        "srv" = 3;
        # storage (black): VM storage access (Ceph)
        "sto" = 4;
        # transfer (blue): primary router uplink
        "tr" = 6;
        # storage backend (yellow): Ceph replication and migration
        "stb" = 8;
        # transfer 2 (blue): secondary router-router connection
        "tr2" = 14;
        # gocept office
        "gocept" = 15;
        # frontend (yellow): additional fe needed on some switches
        "fe2" = 16;
        # servers/backend (red): additional srv needed on some switches
        "srv2" = 17;
        # transfer 3 (blue): tertiary router-router connection
        "tr3" = 18;
        # dynamic hardware pool: local endpoints for Kamp DHP tunnels
        "dhp" = 19;
      };

      mtus = {
        "sto" = 9000;
        "stb" = 9000;
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
        # directory service discovery or just make them part of the router and
        # backup server role.
        dev = [ "eddie" "kenny00" ];
        whq = [ "lou" "kenny01" ];
        rzob = [ "kenny06" "kenny07" ];
        rzrl1 = [ "kenny02" "kenny03" ];
      };

      adminKeys = {
        directory = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDSejGFORJ7hlFraV3caVir3rWlo/QcsWptWrukk2C7eaGu/8tXMKgPtBHYdk4DYRi7EcPROllnFVzyVTLS/2buzfIy7XDjn7bwHzlHoBHZ4TbC9auqW3j5oxTDA4s2byP6b46Dh93aEP9griFideU/J00jWeHb27yIWv+3VdstkWTiJwxubspNdDlbcPNHBGOE+HNiAnRWzwyj8D0X5y73MISC3pSSYnXJWz+fI8IRh5LSLYX6oybwGX3Wu+tlrQjyN1i0ONPLxo5/YDrS6IQygR21j+TgLXaX8q8msi04QYdvnOqk1ntbY4fU8411iqoSJgCIG18tOgWTTOcBGcZX directory@directory.fcio.net";
        ctheune = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA/lhMiMJBednrahZUJvb+dZVhLysbcuGf4p2J4D6MU/ ctheune@fourteen-3.local";
        zagy = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKqKaOCYLUxtjAs9e3amnTRH5NM2j0kjLOE+5ZGy9/W4 zagy@drrr.local";
        flanitz = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAg5mbkbBk0dngSVmlZJEH0hAUqnu3maJzqEV9Su1Cff flanitz";
        cs = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKIlrvXV9TzM1uppd8oAbph1dcab6h28VZSUthsp2eZL christians@colbert";
        ts = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOpJ59uGzQAB/n9YFQoOPWHiUFaKPGj2OivAxQmTkeyN ts";
        nm = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDFBloz5mf4SxX0/GwvOmTD2itWTRjyrmxh13Nzc2oSP nm";
        os = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJemLKFmr09o6zBscLJSD3KcAs/dnIYBjgxYzJ59VvHx os@Olivers-MBP-3";
      };

    };

    ids.uids = {
      # Our custom services
      sensuclient = 31004;
      powerdns = 31005;
      tideways = 31006;
      coredns = 31007;

      # removed by upstream, we want to keep it
      memcached = 177;
      redis = 181;
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

      # Global permissions granted by user membership in a special resource group.
      admins = 2003;

      # Our custom services
      sensuclient = 31004;
      powerdns = 31005;
      tideways = 31006;
    };

  };
}
