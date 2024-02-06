{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus;

  fclib = config.fclib;

  interfaces = filter (i: i.vlan != "ipmi" && i.vlan != "lo") (lib.attrValues fclib.network);
  managedInterfaces = filter (i: i.policy != "unmanaged" && i.policy != "null") interfaces;
  physicalInterfaces = filter (i: i.policy != "vxlan" && i.policy != "underlay") managedInterfaces;

  nonUnderlayInterfaces = filter (i: i.policy != "underlay") managedInterfaces;
  bridgedInterfaces = filter (i: i.bridged) managedInterfaces;
  vxlanInterfaces = filter (i: i.policy == "vxlan") managedInterfaces;
  ethernetDevices =
    (lib.forEach physicalInterfaces
      (iface: {
        name = if iface.bridged then iface.layer2device else iface.device;
        mtu = iface.mtu;
        mac = iface.mac;
      })
    ) ++
    (if isNull fclib.underlay then []
     else lib.mapAttrsToList
       (name: value: {
         name = name;
         mtu = fclib.underlay.mtu;
         mac = value;
       })
       fclib.underlay.interfaces
    );

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

  interfaceRules = lib.concatMapStrings
    (interface: ''
      SUBSYSTEM=="net" , ATTR{address}=="${interface.mac}", NAME="${interface.name}"
      '') ethernetDevices;
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

      # data structure for all configured interfaces with their IP addresses:
      # { ethfe = { ... }; ethsrv = { }; ... }
      # or
      # { brfe = { ... }; brsrv = { }; ethsto = { }; ... }
      interfaces = listToAttrs ((map (interface:
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

          # Using SLAAC/privacy addresses will cause firewalls to block
          # us internally and also have customers get problems with
          # outgoing connections.
          tempAddress = "disabled";

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
        })) nonUnderlayInterfaces) ++
      (if isNull fclib.underlay then [] else [(
        lib.nameValuePair "underlay" {
          ipv4.addresses = [{
            address = fclib.underlay.loopback;
            prefixLength = 32;
          }];
          tempAddress = "disabled";
          mtu = fclib.underlay.mtu;
        }
      )]) ++
      (if isNull fclib.underlay then [] else
        (map (iface: lib.nameValuePair iface {
          tempAddress = "disabled";
          mtu = fclib.underlay.mtu;
        })
          (attrNames fclib.underlay.interfaces))));

      bridges = listToAttrs (map (interface:
        (lib.nameValuePair
          "${interface.device}"
          { interfaces = interface.attachedDevices; }))
        bridgedInterfaces);

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

      firewall.trustedInterfaces =
        if isNull fclib.underlay || config.flyingcircus.infrastructureModule != "flyingcircus-physical"
        then []
        else [ "brsto" "brstb" ] ++ (attrNames fclib.underlay.interfaces);
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

    services.udev.initrdRules = interfaceRules;
    services.udev.extraRules = interfaceRules;

    services.frr = lib.mkIf (!isNull fclib.underlay) {
      zebra = {
        enable = true;
        config = ''
          frr version 8.5.1
          frr defaults datacenter
          !
          route-map set-source-address permit 1
           set src ${fclib.underlay.loopback}
          exit
          !
          ip protocol bgp route-map set-source-address
        '';
      };
      bfd = {
        enable = true;
      };
      bgp = {
        enable = true;
        config = ''
          frr version 8.5.1
          frr defaults datacenter
          !
          router bgp ${toString fclib.underlay.asNumber}
           bgp router-id ${fclib.underlay.loopback}
           bgp bestpath as-path multipath-relax
           no bgp ebgp-requires-policy
           neighbor switches peer-group
           neighbor switches remote-as external
           neighbor switches capability extended-nexthop
           neighbor switches bfd
           ${lib.concatMapStringsSep "\n "
             (name: "neighbor ${name} interface peer-group switches")
             (attrNames fclib.underlay.interfaces)
           }
           !
           address-family ipv4 unicast
            redistribute connected
            neighbor switches prefix-list underlay-import in
            neighbor switches prefix-list underlay-export out
           exit-address-family
           !
           address-family l2vpn evpn
            neighbor switches activate
            advertise-all-vni
            advertise-svi-ip
            ${ # Workaround for FRR not advertising SVI IP when
               # globally configured
              lib.concatMapStringsSep "\n  "
                (iface: concatStringsSep "\n  " [
                  ("vni " + (toString iface.vlanId))
                  " advertise-svi-ip"
                  "exit-vni"
                ])
                vxlanInterfaces
            }
           exit-address-family
          !
          exit
          !
          ip prefix-list underlay-export seq 1 permit ${fclib.underlay.loopback}/32
          !
          ${lib.concatImapStringsSep "\n"
            (idx: net:
              "ip prefix-list underlay-import seq ${toString idx} permit ${net} le 32"
            )
            fclib.underlay.subnets
           }
          !
          route-map accept-routes permit 1
          exit
        '';
      };
    };

    # Don't automatically create a dummy0 interface when the kernel
    # module is loaded.
    boot.extraModprobeConfig = "options dummy numdummies=0";

    systemd.services =
      let
        sysctlSnippet = ''
          # Disable IPv6 SLAAC (autoconf) on physical interfaces
          sysctl net.ipv6.conf.$IFACE.accept_ra=0
          sysctl net.ipv6.conf.$IFACE.autoconf=0
          sysctl net.ipv6.conf.$IFACE.temp_valid_lft=0
          sysctl net.ipv6.conf.$IFACE.temp_prefered_lft=0
          for oldtmp in `ip -6 address show dev $IFACE dynamic scope global  | grep inet6 | cut -d ' ' -f6`; do
            ip addr del $oldtmp dev $IFACE
          done
        '';
      in
      { nscd.restartTriggers = [
          config.environment.etc."host.conf".source
        ];
      } //
      # These units performing network interface setup must be
      # explicitly wanted by the multi-user target, otherwise they
      # will not get initially added as the individual address units
      # won't get restarted because triggering multi-user.target alone
      # does not propagate to the network target, etc etc.
      (listToAttrs
        ((map (iface:
          (lib.nameValuePair
            "network-link-properties-${iface.name}-phy"
            rec {
              description = "Ensure link properties for physical interface ${iface.name}";
              wantedBy = [ "network-addresses-${iface.name}.service"
                           "multi-user.target" ];
              before = wantedBy;
              path = [ pkgs.nettools pkgs.ethtool pkgs.procps fclib.relaxedIp ];
              script = ''
                IFACE=${iface.name}

                IFACE_DRIVER=$(ethtool -i $IFACE | grep "driver: " | cut -d ':' -f 2 | sed -e 's/ //')
                case $IFACE_DRIVER in
                    e1000|e1000e|igb|ixgbe|i40e)
                        # Set adaptive interrupt moderation. This does increase
                        #
                        echo "Enabling adaptive interrupt moderation ..."
                        ethtool -C "$IFACE" rx-usecs 1 || true
                        # Larger buffers.
                        echo "Setting ring buffer ..."
                        ethtool -G "$IFACE" rx 4096 tx 4096 || true
                        # Large receive offload to reduce small packet CPU/interrupt impact.
                        echo "Enabling large receive offload ..."
                        ethtool -K "$IFACE" lro on || true
                        ;;
                esac

                echo "Disabling flow control"
                ethtool -A $IFACE autoneg off rx off tx off || true

                # Ensure MTU
                ip l set $IFACE mtu ${toString iface.mtu}

                ${sysctlSnippet}
              '';
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
            })) ethernetDevices) ++
        (map (iface:
          (lib.nameValuePair
            "network-link-properties-${iface.device}-virt"
            {
              description = "Ensure link properties for virtual interface ${iface.device}";
              wantedBy = [ "network-addresses-${iface.device}.service"
                           "multi-user.target" ];
              bindsTo = [ "${iface.device}-netdev.service" ];
              after = [ "${iface.device}-netdev.service" ];
              path = [ pkgs.nettools pkgs.procps fclib.relaxedIp ];
              script = ''
                IFACE=${iface.device}
                ${sysctlSnippet}
              '';
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
            }
          )) bridgedInterfaces) ++
        (if isNull fclib.underlay then [] else
          [(lib.nameValuePair
            "network-link-properties-underlay-virt"
            rec {
              description = "Ensure network link properties for virtual interface underlay";
              wantedBy = [ "network-addresses-underlay.service"
                           "multi-user.target" ];
              before = wantedBy;
              path = [ pkgs.nettools pkgs.procps fclib.relaxedIp ];
              script = ''
                IFACE=underlay

                # Create virtual interface underlay
                ip link add $IFACE type dummy

                ip link set $IFACE mtu ${toString fclib.underlay.mtu}

                ${sysctlSnippet}
              '';
              preStop = ''
                IFACE=underlay
                ip link delete $IFACE
              '';
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
            }
          ) (lib.nameValuePair
            "network-underlay-routing-fallback"
            rec {
              description = "Ensure fallback unreachable route for underlay prefixes";
              wantedBy = [ "network-addresses-underlay.service"
                           "multi-user.target" ];
              before = wantedBy;
              after = [ "network-link-properties-underlay-virt.service" ];
              path = [ fclib.relaxedIp ];
              script = ''
                ${lib.concatMapStringsSep "\n"
                  (net: "ip route add unreachable " + net)
                  fclib.underlay.subnets
                 }
              '';
              preStop = ''
                ${lib.concatMapStringsSep "\n"
                  (net: "ip route del unreachable " + net)
                  fclib.underlay.subnets
                 }
              '';
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
            }
          )] ++
          (map (iface: (lib.nameValuePair
            "network-link-properties-${iface}-underlay"
            {
              description = "Ensure link properties for physical underlay interface ${iface}";
              wantedBy = [ "network-addresses-${iface}.service"
                           "multi-user.target" ];
              after = [ "network-link-properties-${iface}-phy.service" ];
              path = [ pkgs.procps ];
              script = ''
                sysctl net.ipv4.conf.${iface}.rp_filter=0
              '';
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
            }
          )) (attrNames fclib.underlay.interfaces)) ++
          (map (iface: (lib.nameValuePair
            "network-link-properties-${iface.layer2device}-virt"
            rec {
              description = "Ensure link properties for virtual interface ${iface.layer2device}";
              wantedBy = [ "network-addresses-${iface.layer2device}.service"
                           "multi-user.target" ];
              before = wantedBy;
              partOf = [ "network-addresses-underlay.service" ];
              path = [ pkgs.nettools pkgs.procps fclib.relaxedIp ];
              script = ''
                IFACE=${iface.layer2device}

                # Create virtual interface ${iface.layer2device}
                ip link add $IFACE type vxlan \
                  id ${toString iface.vlanId} \
                  local ${fclib.underlay.loopback} \
                  dstport 4789 \
                  nolearning

                # Set MTU and layer 2 address
                ip link set $IFACE address ${iface.mac}
                ip link set $IFACE mtu ${toString iface.mtu}

                # Do not automatically generate IPv6 link-local address
                ip link set $IFACE addrgenmode none

                ${sysctlSnippet}
              '';
              preStop = ''
                IFACE=${iface.layer2device}
                ip link delete $IFACE
              '';
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
            })) vxlanInterfaces) ++
          (map (iface: (lib.nameValuePair
             "network-link-properties-${iface.layer2device}-bridged"
             {
               description = "Ensure link properties for bridge port ${iface.layer2device}";
               wantedBy = [ "multi-user.target" ];
               partOf = [ "${iface.device}-netdev.service" ];
               after = [ "${iface.device}-netdev.service" ];

               path = [ fclib.relaxedIp ];
               script = ''
                 ip link set ${iface.layer2device} type bridge_slave neigh_suppress on learning off
               '';
               reload = ''
                 ip link set ${iface.layer2device} type bridge_slave neigh_suppress on learning off
               '';
               unitConfig = {
                 ReloadPropagatedFrom = [ "${iface.device}-netdev.service" ];
               };
               serviceConfig = {
                 Type = "oneshot";
                 RemainAfterExit = true;
               };
             }
           )
          ) vxlanInterfaces))
      ));

    boot.kernel.sysctl = lib.mkMerge [{
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
    }
    (lib.mkIf (cfg.infrastructureModule != "flyingcircus-physical") {
      "net.core.rmem_max" = 8388608;
    })
    (lib.mkIf (cfg.infrastructureModule == "flyingcircus-physical") {
      "vm.min_free_kbytes" = "513690";

      "net.core.netdev_max_backlog" = "300000";
      "net.core.optmem" = "40960";
      "net.core.wmem_default" = "16777216";
      "net.core.wmem_max" = "16777216";
      "net.core.rmem_default" = "8388608";
      "net.core.rmem_max" = "16777216";
      "net.core.somaxconn" = "1024";

      "net.ipv4.tcp_fin_timeout" = "10";
      "net.ipv4.tcp_max_syn_backlog" = "30000";
      "net.ipv4.tcp_slow_start_after_idle" = "0";
      "net.ipv4.tcp_syncookies" = "0";
      "net.ipv4.tcp_timestamps" = "0";
                                  # 1MiB   8MiB    # 16 MiB
      "net.ipv4.tcp_mem" = "1048576 8388608 16777216";
      "net.ipv4.tcp_wmem" = "1048576 8388608 16777216";
      "net.ipv4.tcp_rmem" = "1048576 8388608 16777216";

      "net.ipv4.tcp_tw_recycle" = "1";
      "net.ipv4.tcp_tw_reuse" = "1";

      # Supposedly this doesn't do much good anymore, but in one of my tests
      # (too many, can't prove right now.) this appeared to have been helpful.
      "net.ipv4.tcp_low_latency" = "1";

      # Optimize multi-path for VXLAN (layer3 in layer3)
      "net.ipv4.fib_multipath_hash_policy" = "2";
    })];
  };
}
