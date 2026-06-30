{
  config,
  lib,
  pkgs,
  ...
}:

with builtins;

let
  inherit (config.flyingcircus) location static;
  inherit (config) fclib;
  role = config.flyingcircus.roles.router;
  routers = fclib.findServices "router-router";
  routerNames = map (service: head (lib.splitString "." service.address)) routers;
  otherRouterNames = filter (m: m != config.networking.hostName) routerNames;
  kickInterfaces = pkgs.writeShellApplication {
    name = "kick-interfaces";
    runtimeInputs = with pkgs; [ ethtool ];
    text = lib.readFile ./kick-interfaces.sh;
  };
  checkFloodSuppression =
    with pkgs;
    writeScript "check-flood-suppression" ''
      #! ${runtimeShell}
      set -euo pipefail
      IFACE="$1"

      if ip -d -j link show "$IFACE" | jq -e '.[] | .linkinfo.info_slave_data.neigh_suppress' >/dev/null;
      then
          echo "CRITICAL: $IFACE: flood suppression enabled on interface -- this should be disabled!"
          echo
          echo "Run 'ip link set $IFACE type bridge_slave neigh_suppress off' to fix"
          exit 2
      else
          echo "OK: $IFACE: flood suppression is disabled"
      fi
    '';

  uplinkInterfaces = map (network: fclib.network."${network}".interface) (
    fclib.filterConfiguredNetworks role.routerUplinkNetworks
  );

  gatewayInterfaces = map (network: fclib.network."${network}") role.routerGatewayNetworks;

  martianIptablesInput = (
    lib.concatMapStringsSep "\n" (
      network:
      lib.concatMapStringsSep "\n" (
        iface: "${fclib.iptables network} -A nixos-fw -i ${iface} " + "-s ${network} -j DROP"
      ) uplinkInterfaces
    ) role.martianNetworks
  );

  martianIptablesForward = (
    lib.concatMapStringsSep "\n"
      (
        network:
        lib.concatMapStringsSep "\n" (
          iface: "${fclib.iptables network} -A fc-router-forward -i ${iface} " + "-s ${network} -j DROP"
        ) uplinkInterfaces
      )
      # Also drop link-local addresses here.
      (role.martianNetworks ++ [ "fe80::/10" ])
  );

  locationSensuServer = lib.findFirst (
    s: s.service == "sensuserver-source-address"
  ) null config.flyingcircus.encServices;

  sensuSourceAddress = head (filter (i: fclib.isIp4 i) (locationSensuServer.ips));

  routedVrfsEnabled = any (net: net.linktype == "routed") (attrValues fclib.network);
in
{
  options = {
    flyingcircus.roles.router = with lib; {
      enable = mkEnableOption "Router";
      supportsContainers = fclib.mkDisableDevhostSupport;
      isPrimary = mkOption {
        type = types.bool;
        default = false;
      };
      primarySpecialisationConfig = mkOption {
        type = types.attrs;
        internal = true;
        readOnly = true;
        default = {
          system.nixos.tags = [ "primary" ];
          flyingcircus.roles.router.isPrimary = true;
          environment.etc."is_primary".text = "";
          environment.etc."specialisation".text = "primary";
        };
        description = "Internal helper for exposing the specialisation config
          of the primary role to the NixOS test.";
      };

      routerUplinkNetworks = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Names of VLANs on which this router accepts connectivity to the outside world";
      };
      routerDownlinkNetworks = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Names of VLANs on which this router provides external connectivity to other routers";
      };
      routerGatewayNetworks = mkOption {
        type = types.listOf types.str;
        default = [
          "mgm"
          "srv"
          "fe"
        ];
        description = "Names of VLANs on which this router provides gateway services";
      };
      floatingGatewayNetworks = mkOption {
        type = types.listOf types.str;
        default = role.routerGatewayNetworks;
        description = "Names of VLANs on which there are floating addresses shared between multiple routers";
      };

      martianNetworks = mkOption {
        type = types.listOf types.str;
        default = fclib.defaultMartianNetworks;
        visible = false;
        description = "Networks considered invalid as source addresses or as forwarding destinations";
      };

      dhcpResolversV4 = mkOption {
        type = types.listOf (types.addCheck types.str fclib.isIp4);
        # pass the system resolver configuration through to dhcp.
        default = filter fclib.isIp4 config.networking.nameservers;
        description = "IPv4 DNS resolvers to be advertised in DHCP";
      };
      dhcpResolversV6 = mkOption {
        type = types.listOf (types.addCheck types.str fclib.isIp6);
        default =
          # networking.nameservers never uses IPv6 resolvers, fall
          # back to static data.
          if (hasAttr location config.flyingcircus.static.nameservers6) then
            config.flyingcircus.static.nameservers6."${location}"
          else
            [ ];
        description = "IPv6 DNS resolvers to be advertised in DHCPv6";
      };
    };
  };

  imports = [
    ./bind.nix
    ./bird2.nix
    ./keepalived.nix
    ./bird2-vrf-bridge.nix
    ./chrony.nix
    ./kea.nix
    ./pmacctd.nix
    ./radvd.nix
    ./trafficclient.nix
  ];

  config = lib.mkIf role.enable {
    assertions = [
      {
        assertion = (location != "standalone") -> (role.routerUplinkNetworks != [ ]);
        message = "Router must have uplink networks configured";
      }
    ];

    flyingcircus.networking.enableInterfaceDefaultRoutes = false;
    flyingcircus.networking.assignVrfRoutes = routedVrfsEnabled;

    boot.kernel.sysctl = {
      # It's a router: we want forwarding, obviously
      "net.ipv4.conf.all.forwarding" = fclib.mkOverridePlatformModule 1;
      "net.ipv4.conf.default.forwarding" = fclib.mkOverridePlatformModule 1;
      "net.ipv4.ip_forward" = fclib.mkOverridePlatformModule 1;
      "net.ipv6.conf.all.forwarding" = fclib.mkOverridePlatformModule 1;
      "net.ipv6.conf.default.forwarding" = fclib.mkOverridePlatformModule 1;

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
    }
    // lib.optionalAttrs routedVrfsEnabled {
      # Accept incoming connections received in VRFs (i.e. not in the
      # default routing table). This means that e.g. DNS requests to
      # the resolver received from hosts connected through a VRF
      # network will be accepted instead of being rejected as if the
      # port were unreachable.
      "net.ipv4.tcp_l3mdev_accept" = true;
      "net.ipv4.udp_l3mdev_accept" = true;
    };

    services.openssh.extraConfig = ''
      # Protect routers more aggressively against DOS on the MaxStartup settings.
      # We do not support password logins, so a small login grace time helps
      # reducing unauthenticated sessions piling up.
      LoginGraceTime 10
      MaxStartups 100:30:500
    '';

    environment.etc."specialisation".text = lib.mkDefault "";

    environment.systemPackages = with pkgs; [
      kickInterfaces
    ];

    networking.firewall.extraCommands = (
      lib.concatStringsSep "\n" [
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
          ${lib.optionalString (locationSensuServer != null) ''
            # allow SSH from the sensu server in order to remotely monitor switches
            iptables -A fc-router-forward -i ${fclib.network.fe.interface} -o ${fclib.network.mgm.interface} -s ${sensuSourceAddress} -p tcp --dport 22 -j ACCEPT
          ''}
          ip46tables -A fc-router-forward -o ${fclib.network.mgm.interface} -j REJECT

          #############
          # Protect SRV
          ip46tables -A fc-router-forward -o ${fclib.network.srv.interface} -p tcp --dport 22 -j ACCEPT
          ip46tables -A fc-router-forward -o ${fclib.network.srv.interface} -p tcp --dport 80 -j ACCEPT
          ip46tables -A fc-router-forward -o ${fclib.network.srv.interface} -p tcp --dport 443 -j ACCEPT
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
          ${lib.concatMapStringsSep "\n" (
            link: "ip46tables -A fc-router-forward -o ${link.link} -j REJECT"
          ) fclib.underlay.links}
          ${lib.concatMapStringsSep "\n" (
            link: "ip46tables -A fc-router-forward -i ${link.link} -j REJECT"
          ) fclib.underlay.links}
        '')
      ]
    );

    networking.nat.extraCommands = ''
      #############
      # Masquerading rules for the uplink interfaces
      ${lib.concatMapStringsSep "\n" (iface: ''
        iptables -t nat -A nixos-nat-post -o ${iface} -s 172.16.0.0/12 -j MASQUERADE
        iptables -t nat -A nixos-nat-post -o ${iface} -s 10.0.0.0/8 -j MASQUERADE
      '') uplinkInterfaces}
    '';

    networking.firewall.extraStopCommands = ''
      ip46tables -D FORWARD -j fc-router-forward || true
      ip46tables -F fc-router-forward 2>/dev/null || true
      ip46tables -X fc-router-forward 2>/dev/null || true
    '';

    flyingcircus.firewall.enableSrvRgFirewall = false;

    systemd.services =
      (listToAttrs (
        lib.forEach (filter (iface: iface.policy == "vxlan") gatewayInterfaces) (
          iface:
          lib.nameValuePair "network-bridge-suppress-flooding-${iface.link}" {
            enable = fclib.mkPlatform false;
          }
        )
      ))
      // {
        keepalived.wantedBy = [ "multi-user.target" ];
      };

    # the upstream module does not start keepalived immediately on
    # boot in order to prevent it from immediately switching into
    # master state, instead using a timer to defer the start by a few
    # seconds. this has the problem that if keepalived crashes for
    # some reason the next switch-to-configuration run will not
    # attempt to restart it as it is not wanted by
    # multi-user.target. we drop this layer of indirection to allow a
    # crashed keepalived to be recovered.
    systemd.timers.keepalived-boot-delay.enable = fclib.mkPlatform false;

    specialisation.primary = {
      configuration = role.primarySpecialisationConfig;
    };

    systemd.tmpfiles.rules = [
      "d /run/sensuclient 0755 sensuclient sensuclient -"
    ];

    flyingcircus.services.sensu-client = {
      checks = {
        neighbour_cache = {
          notification = "Kernel neighbour cache is too full";
          # Poll frequently in order to try to detect problems which
          # occur suddenly before they wipe the router out.
          interval = 60;
          command = "${pkgs.fc.neighbour-cache-monitor}/bin/neighbour-cache-monitor sensu-check -s /run/sensuclient/neighbour_cache_state.json";
        };
      }
      // (listToAttrs (
        lib.forEach (filter (iface: iface.policy == "vxlan") gatewayInterfaces) (
          iface:
          lib.nameValuePair "flood_suppression_iface_${iface.link}" {
            notification = "Flood suppression is erroneously enabled";
            interval = 300;
            command = "${checkFloodSuppression} ${iface.link}";
          }
        )
      ))
      // (lib.optionalAttrs routedVrfsEnabled {
        vrf_default_route = {
          notification = "VRFs have default routes";
          interval = 600;
          command =
            let
              nets = filter (n: n.linktype == "routed") (attrValues fclib.network);
            in
            "${pkgs.fc.check-vrf-default-routes}/bin/check_vrf_default_routes ${
              lib.concatMapStringsSep " " (n: n.vrfInterface) nets
            }";
        };
      });

      expectedConnections = {
        warning = 18000;
        critical = 25000;
      };
    };

    flyingcircus.services.telegraf.inputs.exec = [
      {
        commands = [ "${pkgs.fc.neighbour-cache-monitor}/bin/neighbour-cache-monitor telegraf-metrics" ];
        timeout = "10s";
        data_format = "json";
        name_override = "neighbour";
        tag_keys = [ "family" ];
      }
    ];

    flyingcircus.agent = {
      maintenance.router = {
        enter =
          let
            nodeArgs = lib.concatMapStrings (u: " --in-service ${u}") otherRouterNames;
            script = pkgs.writeScript "router-agent-enter-maintenance" ''
              set -e
              # Check if all other routers are in service, signal "tempfail" otherwise.
              fc-maintenance constraints --failure-exit-code 75 ${nodeArgs}
              # Returns 75 if switch to secondary timed out or
              # keepalived is in failed/stop state.
              fc-keepalived enter-maintenance
            '';
          in
          "${script}";

        leave = ''
          fc-keepalived leave-maintenance
        '';
      };
    };
  };
}
