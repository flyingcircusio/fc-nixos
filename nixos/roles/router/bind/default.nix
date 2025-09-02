{
  config,
  pkgs,
  lib,
  ...
}:

with builtins;

let
  inherit (config) fclib;
  role = config.flyingcircus.roles.router;
  inherit (config.flyingcircus) location;
  nameservers = [
    "ns.whq.gocept.net"
    "ns.rzob.gocept.net"
  ];
  bindUser = config.systemd.services.bind.serviceConfig.User;

  namedConfig = pkgs.writeText "named.conf" ''
    include "/etc/bind/acl.conf";

    options {
    	directory "/var/cache/named";
    	pid-file "/run/named/named.pid";

    	listen-on-v6 { any; };

      ${lib.optionalString (
        role.sourceAddressV4 != null
      ) "query-source address ${role.sourceAddressV4};"}
      ${lib.optionalString (
        role.sourceAddressV6 != null
      ) "query-source-v6 address ${role.sourceAddressV6};"}

    	allow-query {
    		any;
    	};

    	allow-query-cache {
    		/* Use the cache for the "trusted" ACL. */
    		"gocept.net";
    		"hetzner";
    	};

    	allow-recursion {
    		/* Only trusted addresses are allowed to use recursion. */
    		"gocept.net";
    	};

    	allow-transfer {
    		"gocept.net";
    		"hetzner";
    	};

    	allow-update {
    		/* Don't allow updates, e.g. via nsupdate. */
    		none;
    	};

    	/*
    	 * As of bind 9.8.0:
    	 * "If the root key provided has expired,
    	 * named will log the expiration and validation will not work."
    	 */
    	dnssec-validation auto;

    	forwarders {
    		9.9.9.9;
    		149.112.112.112;
    		2620:fe::fe;
    		2620:fe::9;
    	};
    	/* We originally used "forward only" but Quad9 sometimes does have issues
    	   and then we immediately failed. "forward first" allows us to use quad9
    	   wherever possible and if they return SERVFAIL or similar we go back
    	   to the root nameservers. I _think_ this does circumvent the security
    	   blocks which we aren't too happy about anyway.
    	 */
    	forward first;

    	/* if you have problems and are behind a firewall: */
    	//query-source address * port 53;
    };


    /* You can enable/disable detailed debug logging using:

       $ rndc  -k /etc/bind/rndc.key notrace
       $ rndc  -k /etc/bind/rndc.key trace
       $ rndc  -k /etc/bind/rndc.key trace 5

    */

    logging {
    	category cname { debug_log; };
    	category database { debug_log; };
    	category edns-disabled { debug_log; };
    	category lame-servers { debug_log; };
    	category query-errors { debug_log; };
    	category rate-limit { debug_log; };
    	category resolver { debug_log; };
    	category spill { debug_log; };
    	category default { debug_log; };
    	category config { debug_log; };
    	category dispatch { debug_log; };
    	category network { debug_log; };
    	category general { debug_log; };

    	channel debug_log {
    		file "/var/log/bind/debug.log" versions 50 size 200m suffix timestamp;
    		print-time yes;
    		print-category yes;
    		print-severity yes;
    		severity dynamic;
    	};
    };

    include "/etc/bind/rndc.key";
    controls {
    	inet 127.0.0.1 port 953 allow { 127.0.0.1/32; ::1/128; } keys { "rndc-key"; };
    };

    view "internal" {
    	match-clients { "gocept.net"; };

    	zone "localhost" IN {
    		type master;
    		file "/etc/bind/pri/localhost.zone";
    		allow-update { none; };
    		notify no;
    	};

    	zone "127.in-addr.arpa" IN {
    		type master;
    		file "/etc/bind/pri/127.zone";
    		notify no;
    	};

    	include "/etc/bind/internal-zones.conf";

    };

    view "external" {
    	match-clients { any; };

    	include "/etc/bind/external-zones.conf";
    };
  '';
in
lib.mkIf role.enable {
  environment.etc =
    (builtins.mapAttrs (_: file: file // { user = bindUser; }) {

      # Note: all files that we change here that implicitly change the config
      # must also be added to the reload triggers for the service below!
      "bind/acl.conf".text = ''
        acl "gocept.net" {
            127.0.0.0/8;
            ::/64;
            ${lib.concatStringsSep "\n" (map (n: "    ${n};") fclib.networks.all)}
        };

        acl "hetzner" {
            # ns1.first-ns.de
            213.239.242.238;
            2a01:4f8:0:a101::a:1;
            # robotns2.second-ns.de
            213.133.105.6;
            2a01:4f8:d0a:2004::2;
            # robotns3.second-ns.com
            193.47.99.3;
            2a00:1158:4::add:a3;
        };
      '';
      "bind/pri/127.zone".source = ./127.zone;
      "bind/pri/localhost.zone".source = ./localhost.zone;
      "bind/pri/gocept.net-internal.zone.static".source = ./gocept.net-internal.zone.static;
      "bind/pri/gocept.net.zone.static".source = ./gocept.net.zone.static;
      "bind/pri/1.0.1.0.8.4.2.0.2.0.a.2.zone".source = ./1.0.1.0.8.4.2.0.2.0.a.2.zone;
    })
    // {

      "local/configure-zones.cfg".text = ''
        [settings]
        pridir = /etc/bind/pri
        ttl = 7200
        suffix = gocept.net
        nameservers = ${lib.concatStringsSep ", " nameservers}
        reload = systemctl reload bind

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

        # bug: fc-zones does not correctly support ipv6 prefixes which don't lie on a
        # nibble boundary, so we have to round the prefix length up to the next nibble
        # and then split the prefixes into subnets there. see also:
        # https://docs.db.ripe.net/Database-Support/Configuring-Reverse-DNS/#dealing-with-multiple-zones-for-one-address-block

        # 2a06:3a80::/29
        2a06:3a80::/32 =
        2a06:3a81::/32 =
        2a06:3a82::/32 =
        2a06:3a83::/32 =
        2a06:3a84::/32 =
        2a06:3a85::/32 =
        2a06:3a86::/32 =
        2a06:3a87::/32 =

        # 2a07:ed00::/29
        2a07:ed00::/32 =
        2a07:ed01::/32 =
        2a07:ed02::/32 =
        2a07:ed03::/32 =
        2a07:ed04::/32 =
        2a07:ed05::/32 =
        2a07:ed06::/32 =
        2a07:ed07::/32 =
      '';
    };

  networking.resolvconf.useLocalResolver = false;

  environment.systemPackages = [
    # I want rndc to be available
    pkgs.bind # config.services.bind.package didn't work
  ];

  services.bind = {
    enable = true;
    directory = "/var/cache/named";
    configFile = namedConfig;
  };

  systemd.services.bind = {
    serviceConfig = {
      Restart = "always";
      ReadWritePaths = [
        "/var/log/bind/"
        "/etc/bind/"
      ];
    };

    restartTriggers = [
      config.environment.etc."bind/acl.conf".source
      config.environment.etc."bind/pri/127.zone".source
      config.environment.etc."bind/pri/localhost.zone".source
      config.environment.etc."bind/pri/gocept.net-internal.zone.static".source
      config.environment.etc."bind/pri/gocept.net.zone.static".source
      config.environment.etc."bind/pri/1.0.1.0.8.4.2.0.2.0.a.2.zone".source
    ];
  };

  systemd.tmpfiles.rules = [
    "d /var/log/bind 0755 ${bindUser} nogroup 180d"
    "z /etc/bind 0755 ${bindUser}"
  ];

  flyingcircus.services.sensu-client.checks.bind_resolver = {
    notification = "Bind can resolve hostnames";
    command = "check_dig -H localhost -l flyingcircus.io";
  };

  networking.firewall.extraCommands = ''
    ip46tables -A nixos-fw -p tcp --dport 53 -j nixos-fw-accept
    ip46tables -A nixos-fw -p udp --dport 53 -j nixos-fw-accept
  '';

}
