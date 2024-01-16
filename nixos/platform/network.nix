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
          )]) ++
        (if isNull fclib.underlay then [] else (map (iface:
          lib.nameValuePair
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

                # Create virtual inteface ${iface.layer2device}
                ip link add $IFACE type vxlan \
                  id ${toString iface.vlanId} \
                  local ${fclib.underlay.loopback} \
                  dstport 4789 \
                  nolearning

                # Set MTU and layer 2 address
                ip link set $IFACE address ${iface.mac}
                ip link set $IFACE mtu ${toString iface.mtu}

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
            }
        ) vxlanInterfaces))
      ));

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
