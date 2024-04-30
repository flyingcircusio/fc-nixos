{ config, lib, pkgs, ... }:

with builtins;

let
  inherit (config.flyingcircus) location static;
  inherit (config) fclib;
  role = config.flyingcircus.roles.router;
  kickInterfaces = fclib.writeShellApplication {
    name = "kick-interfaces";
    runtimeInputs = with pkgs; [ ethtool ];
    text = lib.readFile ./kick-interfaces.sh;
  };

  uplinkInterfaces = map
    (network: fclib.network."${network}".interface)
    static.routerUplinkNetworks."${location}";

  martianNetworks =
    lib.filter
      (n: n != "")
      (lib.splitString "\n" (lib.readFile ./martian_networks));

  martianIptablesInput =
    (lib.concatMapStringsSep "\n"
      (network:
        lib.concatMapStringsSep "\n"
          (iface:
            "${fclib.iptables network} -A nixos-fw -i ${iface} " +
            "-s ${network} -j DROP")
          uplinkInterfaces)
      martianNetworks);

  martianIptablesForward =
    (lib.concatMapStringsSep "\n"
      (network:
        lib.concatMapStringsSep "\n"
          (iface:
            "${fclib.iptables network} -A fc-router-forward -i ${iface} " +
            "-s ${network} -j DROP")
          uplinkInterfaces)
      # Also drop link-local addresses here.
      (martianNetworks ++ [ "fe80::/10" ]));

  locationSensuServer = lib.findFirst
    (s: s.service == "sensuserver-source-address")
    null
    config.flyingcircus.encServices;

  sensuSourceAddress = head (filter (i: fclib.isIp4 i) (locationSensuServer.ips));
in
{
  options = {
    flyingcircus.roles.router = with lib; {
      enable = mkEnableOption "Router";
      supportsContainers = fclib.mkDisableContainerSupport;
      isPrimary = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };

  imports = [
    ./bind
    ./bird2
    ./keepalived
    ./chrony.nix
    ./dhcpd.nix
    ./radvd.nix
  ];

  config = lib.mkIf role.enable {

    flyingcircus.networking.enableInterfaceDefaultRoutes = false;

    boot.kernel.sysctl = {
      # It's a router: we want forwarding, obviously
      "net.ipv4.conf.all.forwarding" = 1;
      "net.ipv4.conf.default.forwarding" = 1;
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv6.conf.default.forwarding" = 1;

      # Avoid neighbour discovery table overflow on our relatively large segments
      "net.ipv4.neigh.default.gc_thresh1" = lib.mkOverride 90 4096;
      "net.ipv4.neigh.default.gc_thresh2" = lib.mkOverride 90 16384;
      "net.ipv4.neigh.default.gc_thresh3" = lib.mkOverride 90 32768;
      "net.ipv6.neigh.default.gc_thresh1" = lib.mkOverride 90 4096;
      "net.ipv6.neigh.default.gc_thresh2" = lib.mkOverride 90 16384;
      "net.ipv6.neigh.default.gc_thresh3" = lib.mkOverride 90 32768;

      # fair queuing + codel to avoid buffer bloat in WAN
      "net.core.default_qdisc" = "fq_codel";

      # Ensure proper conntracking configuration: if we run out of entries then
      # packets will get dropped.
      #
      # TODO wrong URL
      # See https://stats.flyingcircus.io/grafana/dashboard/db/kenny01-conntrack
      # for current usage statistics
      #
      # This should use about 300-500 MiB with ~32 entries in each bucket
      # https://johnleach.co.uk/words/372/netfilter-conntrack-memory-usage
      "net.netfilter.nf_conntrack_max" = lib.mkOverride 90 1048576;
      "net.netfilter.nf_conntrack_buckets" = 32768;
    };

    environment.etc."specialisation".text = lib.mkDefault "";

    environment.systemPackages = with pkgs; [
      kickInterfaces
      pmacct
    ];

    environment.shellAliases = {
    };

    networking.firewall.extraCommands =
      (lib.concatStringsSep "\n" [
        martianIptablesInput
        ''
        ip46tables -N fc-router-forward || true
        ip46tables -A FORWARD -j fc-router-forward
        ''
        martianIptablesForward
        ''
        # Suppress multicast forwarding
        iptables -A fc-router-forward -s 224.0.0.0/4 -j DROP
        iptables -A fc-router-forward -d 224.0.0.0/4 -j DROP
        ip6tables -A fc-router-forward -s ff::/8 -j DROP
        ip6tables -A fc-router-forward -d ff::/8 -j DROP

        # memcached UDP amplification attacks (see also memcached.pp)
        ip46tables -A fc-router-forward -p udp --dport 11211 -j REJECT
        ip46tables -A fc-router-forward -p tcp --dport 11211 -j REJECT

        # SunRPC/NFS/et al.
        ip46tables -A fc-router-forward -p udp --dport 111 -j REJECT
        ip46tables -A fc-router-forward -p tcp --dport 111 -j REJECT

        # Always allow ICMP
        iptables -A fc-router-forward -p icmp -j ACCEPT
        ip6tables -A fc-router-forward -p icmpv6 -j ACCEPT

        # Always allow related traffic
        ip46tables -A fc-router-forward -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

        #############
        # Protect MGM
        iptables -A fc-router-forward -o ${fclib.network.mgm.interface} -p icmp -j ACCEPT
        ip6tables -A fc-router-forward -o ${fclib.network.mgm.interface} -p icmpv6 -j ACCEPT
        # allow prometheus
        ip46tables -A fc-router-forward -o ${fclib.network.mgm.interface} -p tcp --dport 9126 -j ACCEPT
        # allow SSH from the sensu server in order to remotely monitor switches
        iptables -A fc-router-forward -i ${fclib.network.fe.interface} -o ${fclib.network.mgm.interface} -s ${sensuSourceAddress} -p tcp --dport 22 -j ACCEPT
        ip46tables -A fc-router-forward -o ${fclib.network.mgm.interface} -j REJECT

        #############
        # Protect SRV
        ip46tables -A fc-router-forward -o ${fclib.network.srv.interface} -p tcp --dport 22 -j ACCEPT
        ip46tables -A fc-router-forward -o ${fclib.network.srv.interface} -p tcp --dport 8140 -j ACCEPT
        ip46tables -A fc-router-forward -o ${fclib.network.srv.interface} -j REJECT

        #############
        # Control FE and TR traffic
        # We generally allow all traffic on FE
        ip46tables -A fc-router-forward -o ${fclib.network.fe.interface} -j ACCEPT

        # XXX we don't want accidents but need to allow traffic to the outside
        # but don't generally know which transfer interfaces are active.
        # If we can limit the open forwarding towards the internet and have a
        # fall-through default of "REJECT" for everything else then terminating
        # an arbitrary VXLAN on the router doesn't automatically cause
        # everything to be forwarded.

        ''
        (lib.optionalString (!isNull fclib.underlay) ''
        #############
        # Protect UL
        # Forwarding should not be permitted onto or out of the underlay network
        ${lib.concatMapStringsSep "\n"
          (link: "ip46tables -A fc-router-forward -o ${link.link} -j REJECT")
          fclib.underlay.links
         }
        ${lib.concatMapStringsSep "\n"
          (link: "ip46tables -A fc-router-forward -i ${link.link} -j REJECT")
          fclib.underlay.links
         }
        '')
      ]);

    networking.nat.extraCommands = ''
      #############
      # Masquerading rules for the uplink interfaces
      ${lib.concatMapStringsSep "\n"
        (iface: "iptables -t nat -A nixos-nat-post -o ${iface} -s 172.16.0.0/12 -j MASQUERADE")
        uplinkInterfaces
      }
    '';

    networking.firewall.extraStopCommands = ''
      ip46tables -D FORWARD -j fc-router-forward || true
      ip46tables -F fc-router-forward 2>/dev/null || true
      ip46tables -X fc-router-forward 2>/dev/null || true
    '';

    services.logrotate.extraConfig = ''
    '';

    specialisation.primary = {
      configuration = {
        system.nixos.tags = [ "primary" ];
        flyingcircus.roles.router.isPrimary = true;
        environment.etc."is_primary".text = "";
        environment.etc."specialisation".text = "primary";
      };
    };

    flyingcircus.services.sensu-client = {
      checks = {
      };

      expectedConnections = {
        warning = 18000;
        critical = 25000;
      };
    };

    flyingcircus.agent = {
      extraPreCommands = ''
        fc-dhcpd -4 -o /etc/nixos/localconfig-dhcpd4.conf ${location}
        fc-dhcpd -6 -o /etc/nixos/localconfig-dhcpd6.conf ${location}
        # Updates files in /etc/bind and /etc/bind/pri where also Nix-generated config exists.
        fc-zones
      '';
    };

  };
}
