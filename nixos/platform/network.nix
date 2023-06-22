{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus;

  fclib = config.fclib;

  interfaces = filter (i: i.vlan != "ipmi" && i.vlan != "lo") (lib.attrValues fclib.network);

  location = lib.attrByPath [ "parameters" "location" ] "" cfg.enc;

  # generally use DHCP in the current location?
  allowDHCP = location:
    if hasAttr location cfg.static.allowDHCP
    then cfg.static.allowDHCP.${location}
    else false;

  # add srv addresses from my own resource group to /etc/hosts
  hostsFromEncAddresses = encAddresses:
    let
      recordToEtcHostsLine = r:
      let hostName =
        if config.networking.domain != null
        then "${r.name}.${config.networking.domain} ${r.name}"
        else "${r.name}";
      in
        "${fclib.stripNetmask r.ip} ${hostName}";
    in
      # always mention IPv6 addresses first to get predictable behaviour
      lib.concatMapStringsSep "\n" recordToEtcHostsLine
        ((filter (a: fclib.isIp6 a.ip) encAddresses) ++
         (filter (a: fclib.isIp4 a.ip) encAddresses));

in
{

  config = rec {
    environment.etc."host.conf".text = ''
      order hosts, bind
      multi on
    '';

    environment.systemPackages = with pkgs; [
      ethtool
    ];

    networking = {

      # FQDN and host name should resolve to the SRV address
      # (set by hostsFromEncAddresses) and not 127.0.0.1.
      # Restores old behaviour that we know from 15.09.
      # -> #PL-129549
      hosts = lib.mkOverride 90 {};

      nameservers =
        if (hasAttr location cfg.static.nameservers)
        then cfg.static.nameservers.${location}
        else [];

      # Using SLAAC/privacy addresses will cause firewalls to block us
      # internally and also have customers get problems with outgoing
      # connections.
      tempAddresses = "disabled";

      # data structure for all configured interfaces with their IP addresses:
      # { ethfe = { ... }; ethsrv = { }; ... }
      interfaces = listToAttrs (map (interface:
        (lib.nameValuePair "${interface.device}" {
          ipv4.addresses = interface.v4.attrs;
          ipv4.routes =
            let
              defaultRoutes = map (gateway:
                {
                  address = "0.0.0.0";
                  prefixLength = 0;
                  via = gateway;
                  options = { metric = toString interface.priority; };
                }) interface.v4.defaultGateways;

              # To select the correct interface, add routes for other subnets
              # in which this machine doesn't have its own address.
              # We did this with policy routing before. After deactivating it,
              # we had problems with srv traffic going out via fe because its default route
              # has higher priority.
              additionalRoutes = map
                (net: { address = net.network; inherit (net) prefixLength; })
                (filter (n: n.addresses == []) interface.v4.networkAttrs);
            in
              defaultRoutes ++ additionalRoutes;

          ipv6.addresses = interface.v6.attrs;

          ipv6.routes =
            let
              defaultRoutes = map (gateway:
                { address = "::";
                  prefixLength = 0;
                  via = gateway;
                  options = { metric = toString interface.priority; };
                }) interface.v6.defaultGateways;

              additionalRoutes = map
                (net: { address = net.network; inherit (net) prefixLength; })
                (filter (n: n.addresses == []) interface.v6.networkAttrs);
            in
              defaultRoutes ++ additionalRoutes;

          mtu = interface.mtu;
        })) interfaces);

      bridges = listToAttrs (map (interface:
        (lib.nameValuePair
            "${interface.device}"
            { interfaces = interface.attachedDevices; }))
        (filter (interface: interface.bridged) interfaces));

      resolvconf.extraOptions = [ "ndots:1" "timeout:1" "attempts:6" ];

      search = lib.optionals
        (location != "" && config.networking.domain != null)
        [ "${location}.${config.networking.domain}"
          config.networking.domain
        ];

      # DHCP settings: never do IPv4ll and don't use DHCP by default.
      useDHCP = fclib.mkPlatform false;
      dhcpcd.extraConfig = ''
        # IPv4ll gets in the way if we really do not want
        # an IPv4 address on some interfaces.
        noipv4ll
      '';

      extraHosts = lib.optionalString
        (cfg.encAddresses != [])
        (hostsFromEncAddresses cfg.encAddresses);

      wireguard.enable = true;

    };

    flyingcircus.activationScripts = {

      prepare-wireguard-keys = ''
        set -e
        install -d -g root /var/lib/wireguard
        umask 077
        cd /var/lib/wireguard
        if [ ! -e "privatekey" ]; then
          ${pkgs.wireguard-tools}/bin/wg genkey > privatekey
        fi
        chmod u=rw,g-rwx,o-rwx privatekey
        if [ ! -e "publickey" ]; then
          ${pkgs.wireguard-tools}/bin/wg pubkey < privatekey > publickey
        fi
        chgrp service publickey
        chmod u=rw,g=r,o-rwx publickey
        ${pkgs.acl}/bin/setfacl -m g:sudo-srv:r publickey
      '';

    };

    boot.initrd.services.udev.rules = lib.concatMapStrings
      (interface: ''
        SUBSYSTEM=="net" , ATTR{address}=="${interface.mac}", NAME="${interface.physicalDevice}"
        '') interfaces;

    systemd.services =
      let startStopScript = fclib.simpleRouting;
      in
      { nscd.restartTriggers = [
          config.environment.etc."host.conf".source
        ];
      } //
      (listToAttrs
        (map (interface:
          (lib.nameValuePair
            "network-link-properties-${interface.physicalDevice}"
            rec {
              description = "Ensure link properties for ${interface.physicalDevice}";
              # We need to explicitly be wanted by the multi-user target,
              # otherwise we will not get initially added as the individual
              # address units won't get restarted because triggering
              # the multi-user alone does not propagated to the network-target
              # etc. etc.
              wantedBy = [ "network-addresses-${interface.device}.service"
                           "multi-user.target" ];

              before = wantedBy;
              path = [ pkgs.nettools pkgs.ethtool pkgs.procps fclib.relaxedIp];
              script = ''
                IFACE=${interface.physicalDevice}

                IFACE_DRIVER=$(ethtool -i $IFACE | grep "driver: " | cut -d ':' -f 2 | sed -e 's/ //')
                case $IFACE_DRIVER in
                    e1000|e1000e|igb|ixgbe|i40e)
                        # Disable interrupt moderation. We want traffic to leave the buffers
                        # as fast as possible. Specifically on 10G links this can otherwise
                        # quickly saturate the buffers and cause discards or pauses.
                        echo "Disabling interrupt moderation ..."
                        ethtool -C "$IFACE" rx-usecs 0 || true
                        # Larger buffers.
                        echo "Setting ring buffer ..."
                        ethtool -G "$IFACE" rx 4096 tx 4096 || true
                        # Large receive offload to reduce small packet CPU/interrupt impact.
                        echo "Disabling large receive offload ..."
                        ethtool -K "$IFACE" lro off || true
                        ;;
                esac

                echo "Disabling flow control"
                ethtool -A $IFACE autoneg off rx off tx off || true

                # Ensure MTU
                ip l set $IFACE mtu ${toString interface.mtu}

                # Disable IPv6 SLAAC (autoconf) on physical interfaces
                sysctl net.ipv6.conf.$IFACE.accept_ra=0
                sysctl net.ipv6.conf.$IFACE.autoconf=0
                sysctl net.ipv6.conf.$IFACE.temp_valid_lft=0
                sysctl net.ipv6.conf.$IFACE.temp_prefered_lft=0

                # If an interface has previously been managed by dhcpcd this sysctl might be
                # set to a non-zero value, which disables automatic generation of link-local
                # addresses. This can leave the interface without a link-local address when
                # dhcpcd deletes addresses from the interface when it exits. Resetting this
                # to 0 restores the default kernel behaviour.
                sysctl net.ipv6.conf.$IFACE.addr_gen_mode=0

                for oldtmp in `ip -6 address show dev $IFACE dynamic scope global  | grep inet6 | cut -d ' ' -f6`; do
                  ip addr del $oldtmp dev $IFACE
                done

                # XXX this needs to trigger properly when brXXX-netdev gets reloaded
                # see the bindsTo dance for qemu bridge reattachment

                # Disable IPv6 SLAAC (autoconf) on interfaces w/ addresses
                sysctl net.ipv6.conf.${interface.device}.accept_ra=0
                sysctl net.ipv6.conf.${interface.device}.autoconf=0
                sysctl net.ipv6.conf.${interface.device}.temp_valid_lft=0
                sysctl net.ipv6.conf.${interface.device}.temp_prefered_lft=0

                # See above.
                sysctl net.ipv6.conf.${interface.device}.addr_gen_mode=0

                for oldtmp in `ip -6 address show dev ${interface.device} dynamic scope global  | grep inet6 | cut -d ' ' -f6`; do
                  ip addr del $oldtmp dev ${interface.device}
                done

              '';
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
            }))
          interfaces));

    boot.kernel.sysctl = {
      "net.ipv4.tcp_congestion_control" = "bbr";
      # Ensure that we can do early binds before addresses are configured.
      "net.ipv4.ip_nonlocal_bind" = "1";
      "net.ipv6.ip_nonlocal_bind" = "1";

      # Ensure dual stack support for binding to [::] for services that
      # only accept a single bind address.
      "net.ipv6.bindv6only" = "0";

      # Ensure that we can use IPv6 as early as possible.
      # This fixes startup race conditions like
      # https://yt.flyingcircus.io/issue/PL-130190
      "net.ipv6.conf.all.optimistic_dad" = 1;
      "net.ipv6.conf.all.use_optimistic" = 1;

      # Ensure we reserve ports as promised to our customers.
      "net.ipv4.ip_local_port_range" = "32768 60999";
      "net.ipv4.ip_local_reserved_ports" = "61000-61999";
      "net.core.rmem_max" = 8388608;
      # Linux currently has 4096 as default and that includes
      # neighbour discovery. Seen on #denog on 2020-11-19
      "net.ipv6.route.max_size" = 2147483647;

      # Ensure we can work in larger vLANs with hundreds of nodes.
      "net.ipv4.neigh.default.gc_thresh1" = 1024;
      "net.ipv4.neigh.default.gc_thresh2" = 4096;
      "net.ipv4.neigh.default.gc_thresh3" = 8192;
      "net.ipv6.neigh.default.gc_thresh1" = 1024;
      "net.ipv6.neigh.default.gc_thresh2" = 4096;
      "net.ipv6.neigh.default.gc_thresh3" = 8192;

      # See PL-130189
      # conntrack entries are created (for v4/v6) if any rules
      # for related/established and/or NATing are used in the
      # PREROUTING hook
      # suppressing/disabling conntrack on individual machines will
      # likely lead to a confusing platform behaviour as we will need
      # connection tracking more and more on VPN servers, container hosts, etc.
      # we already dealt with this in Ceph and have established 250k tracked connections
      # as a reasonable size and I'd suggest generalizing this number to all machines.
      "net.netfilter.nf_conntrack_max" = 262144;
    };
  };
}
