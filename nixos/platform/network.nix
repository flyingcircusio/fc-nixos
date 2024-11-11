{ config, lib, pkgs, utils, ... }:

with builtins;

# XXX test 2

let
  cfg = config.flyingcircus;

  fclib = config.fclib;

  # XXX there's a lot of conditionals here
  interfaces = filter
    (i: i.vlan != "ipmi" && i.vlan != "lo")
    (lib.attrValues fclib.network);

  managedInterfaces = filter
    (i: i.policy != "unmanaged" && i.policy != "null")
    interfaces;

  physicalInterfaces = filter
    (i: i.policy != "vxlan" && i.policy != "underlay")
    managedInterfaces;

  nonUnderlayInterfaces = filter
    (i: i.policy != "underlay")
    managedInterfaces;

  bridgedInterfaces = filter
    (i: i.bridged)
    managedInterfaces;

  vxlanInterfaces = filter
    (i: i.policy == "vxlan")
    managedInterfaces;

  ethernetLinks = let
    # XXX handling this within fclib.network.ul would be great
    underlayLinks = lib.optionals (!isNull fclib.underlay) fclib.underlay.links;

    # The same physical link may be used by multiple distinct
    # interfaces, as is the case with tagged vlans. When physical
    # links are configured, they must have their MTU set to the
    # greatest MTU of all dependent interfaces.
    physicalLinkNames = lib.unique (map (iface: iface.link) physicalInterfaces);
    physicalLinksByMtu = listToAttrs (map (link:
      lib.nameValuePair link
        (lib.foldl
          (prev: next: if next.mtu > (prev.mtu or 0) then next else prev)
          null
          (filter (iface: iface.link == link) physicalInterfaces))
    ) physicalLinkNames);
  in (attrValues physicalLinksByMtu) ++ underlayLinks;

  virtualLinks = let
    allLinks = lib.unique
      (lib.foldl (acc: iface: acc ++ iface.linkStack) [] managedInterfaces);
    ethernetLinkNames = map (iface: iface.link) ethernetLinks;
  in
    lib.subtractLists ethernetLinkNames allLinks;

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

   quoteLabel = replaceStrings ["/"] ["-"];

in
{

  options = {
    flyingcircus.networking.enableInterfaceDefaultRoutes = lib.mkOption {
      type = lib.types.bool;
      description = "Enable default routes for all networks with known default gateways.";
      default = true;
    };
    flyingcircus.networking.monitorLinks = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      description = "Names of ethernet devices to monitor.";
      default = [];
    };
  };

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
      # or
      # { brfe = { ... }; brsrv = { }; ethsto = { }; ... }
      interfaces = listToAttrs ((map (interface:
        (lib.nameValuePair "${interface.interface}" {
          ipv4.addresses = interface.v4.attrs;
          ipv4.routes =
            let
              defaultRoutes = lib.optionals
                (config.flyingcircus.networking.enableInterfaceDefaultRoutes)
                (map (gateway:
                  {
                    address = "0.0.0.0";
                    prefixLength = 0;
                    via = gateway;
                    options = { metric = toString interface.priority; };
                  }) interface.v4.defaultGateways);

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
              defaultRoutes = lib.optionals
                (config.flyingcircus.networking.enableInterfaceDefaultRoutes)
                (map (gateway:
                  { address = "::";
                    prefixLength = 0;
                    via = gateway;
                    options = { metric = toString interface.priority; };
                  }) interface.v6.defaultGateways);

              additionalRoutes = map
                (net: { address = net.network; inherit (net) prefixLength; })
                (filter (n: n.addresses == []) interface.v6.networkAttrs);
            in
              defaultRoutes ++ additionalRoutes;

          mtu = interface.mtu;
        })) nonUnderlayInterfaces) ++
      (lib.optionals (!isNull fclib.underlay) [(
        lib.nameValuePair fclib.underlay.interface {
          ipv4.addresses = [{
            address = fclib.underlay.loopback;
            prefixLength = 32;
          }];
          tempAddress = "disabled";
          mtu = fclib.network.ul.mtu;
        }
      )]) ++
      ((map (iface: lib.nameValuePair iface.link {
          tempAddress = "disabled";
          mtu = iface.mtu;
        })
        fclib.underlay.links or [])));

      bridges = listToAttrs (map (interface:
        (lib.nameValuePair
          "${interface.interface}"
          { interfaces = interface.attachedLinks; }))
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
        lib.optionals (!isNull fclib.underlay && cfg.infrastructureModule == "flyingcircus-physical")
          (map (l: l.link) fclib.underlay.links or []);

      firewall.extraCommands = ''
        # Well-known space needed for IPV6 to function.
        ip6tables -A nixos-fw -s ff0::/12 -j ACCEPT
        # Ignore all other multi-cast traffic.
        ip6tables -A nixos-fw -s ff::/8 -j DROP
        ip6tables -A nixos-fw -d ff::/8 -j DROP
        iptables -A nixos-fw -s 224.0.0.0/4 -j DROP
        iptables -A nixos-fw -d 224.0.0.0/4 -j DROP
      '' +
        # Do not conntrack the VXLAN underlay packets
        lib.optionalString (fclib.underlay != null) (
          lib.concatMapStrings (address: ''
            iptables -t raw -A fc-raw-prerouting -d ${address} -j CT --notrack
            iptables -t raw -A fc-raw-output -s ${address} -j CT --notrack
          '') fclib.network.ul.v4.addresses);
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

    flyingcircus.services.telegraf.inputs = lib.optionalAttrs (cfg.infrastructureModule == "flyingcircus-physical") {
      exec = [{
        commands = [ "${pkgs.fc.telegraf-routes-summary}/bin/telegraf-routes-summary" ];
        timeout = "10s";
        data_format = "json";
        json_name_key = "name";
        tag_keys = [ "family" "path" ];
      }];
    };

    flyingcircus.networking.monitorLinks = ethernetLinks;

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
        extraOptions = [ "-p" "0" ];
        config = ''
          frr version 8.5.1
          frr defaults datacenter
          !
          router bgp ${toString fclib.underlay.asNumber}
           bgp router-id ${fclib.underlay.loopback}
           bgp bestpath as-path multipath-relax
           neighbor switches peer-group
           neighbor switches remote-as external
           neighbor switches capability extended-nexthop
           neighbor switches bfd
           ${lib.concatMapStringsSep "\n "
             (iface: "neighbor ${iface.link} interface peer-group switches")
             fclib.underlay.links
           }
           !
           address-family ipv4 unicast
            redistribute connected
            neighbor switches prefix-list underlay-import in
            neighbor switches prefix-list underlay-export out
            neighbor switches route-map accept-all-routes in
            neighbor switches route-map accept-local-routes out
           exit-address-family
           !
           address-family l2vpn evpn
            neighbor switches activate
            neighbor switches route-map accept-all-routes in
            neighbor switches route-map accept-local-routes out
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
          bgp as-path access-list local-origin seq 1 permit ^$
          !
          route-map accept-local-routes permit 1
           match as-path local-origin
          exit
          !
          route-map accept-all-routes permit 1
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
        '';
      };
    };

    # Don't automatically create a dummy0 interface when the kernel
    # module is loaded.
    boot.extraModprobeConfig = "options dummy numdummies=0";

    systemd.services =
      { nscd.restartTriggers = [
          config.environment.etc."host.conf".source
        ];
        systemd-sysctl.restartTriggers = lib.mkIf (!isNull fclib.underlay) [
          config.environment.etc."sysctl.d/70-fcio-underlay.conf".source
        ];
      } //

      # These units performing network interface setup must be
      # explicitly wanted by the multi-user target, otherwise they
      # will not get initially added as the individual address units
      # won't get restarted because triggering multi-user.target alone
      # does not propagate to the network target, etc etc.
      (listToAttrs (

        (map (iface:
          (lib.nameValuePair
            "${iface.link}-netdev"
            rec {
              description = "Ensure network device settings for ${iface.link}";
              wantedBy = [ "network-setup.service" "multi-user.target"  ];
              requires = [ "network-setup.service" ];
              path = [ pkgs.nettools pkgs.ethtool pkgs.procps fclib.relaxedIp pkgs.jq pkgs.util-linux];
              script = ''
                set -e

                touch /var/lock/interface-rename.lock
                exec 4</var/lock/interface-rename.lock

                echo "Renaming to ${iface.link} ..."

                echo "Acquiring interface renaming lock ..."
                flock -x -w 60 4 || exit 1
                echo "Got interface renaming lock ..."

                # Look up the desired interface's current name by mac address
                interface="$(ip -j -d link show | jq -r '.[] | select(.linkinfo?.info_kind? == null) | select(.address == "${iface.mac}") | .ifname')"

                # XXX properly handle missing MAC address and cause this unit to fail.

                if [[ "$interface" != "${iface.link}" ]]; then
                  echo "Interface is currently known as $interface ..."

                  # Check whether our desired name is also already in use,
                  # rename that one to a unique name.
                  counter=0
                  while ip l show dev ${iface.link} > /dev/null; do
                    echo "${iface.link} is still being used, trying to clean up."
                    # Down the other interface and rename it
                    ip l set ${iface.link} down
                    # Try, don't care if it fails. We check the success on the
                    # next loop.
                    ip l set ${iface.link} name eth$counter || true
                    # The interface's name might not have been it's primary name
                    # but an altname, try to delete that as well.
                    # This looks funny, but we can use the altname to look up the
                    # link to remove the altname ...
                    # don't do this if the name is already gone
                    ip l property del altname ${iface.link} dev ${iface.link} || true
                    counter=$((counter+1))
                  done

                  echo "Performing rename from $interface to ${iface.link}"
                  ip l set $interface down
                  ip l set $interface name ${iface.link}
                fi

                LINK_DRIVER=$(ethtool -i ${iface.link} | grep "driver: " | cut -d ':' -f 2 | sed -e 's/ //')
                case $LINK_DRIVER in
                    e1000|e1000e|igb|ixgbe|i40e)
                        # Set adaptive interrupt moderation. This does increase
                        # latency.
                        echo "Enabling adaptive interrupt moderation ..."
                        ethtool -C "${iface.link}" rx-usecs 1 || true
                        # Larger buffers.
                        echo "Setting ring buffer ..."
                        ethtool -G "${iface.link}" rx 4096 tx 4096 || true
                        # Large receive offload to reduce small packet CPU/interrupt impact.
                        echo "Enabling large receive offload ..."
                        ethtool -K "${iface.link}" lro on || true
                        ;;
                esac

                echo "Disabling flow control"
                ethtool -A ${iface.link} autoneg off rx off tx off || true

                # Ensure MTU
                ip l set ${iface.link} mtu ${toString iface.mtu}

                ''

             + (lib.optionalString (iface.externalLabel != null) ''
                # Add long alternative names according to the external label
                if ip l show dev ${quoteLabel iface.externalLabel} > /dev/null; then
                  # XXX There is an edge case we don't cover here:
                  # if the desired altname is already the primary name of an interface
                  # the altname del will fail and this unit will not come up properly
                  # but that means we notice it and will fix it then.
                  ip l property del altname ${quoteLabel iface.externalLabel} dev ${quoteLabel iface.externalLabel}
                fi
                ip l property add altname ${quoteLabel iface.externalLabel} dev ${iface.link}

              '') + ''
                echo "Releasing lock"
                exec 4>&-
              '';
              preStop = ''
                set -e

                touch /var/lock/interface-rename.lock
                exec 4</var/lock/interface-rename.lock

                echo "Renaming ${iface.link} to neutral name ..."

                echo "Acquiring interface renaming lock ..."
                flock -x -w 60 4 || exit 1
                echo "Got interface renaming lock ..."

                # Shut down the interface so the systemd device unit goes away
                # so we can perform proper renames.
                ip l set ${iface.link} down

                counter=0
                while ip l show dev ${iface.link} > /dev/null; do
                  ip l set ${iface.link} down
                  # Try, don't care if it fails. We check the success on the
                  # next loop.
                  ip l set ${iface.link} name eth$counter || true
                  # don't do this if the name is already gone
                  ip l property del altname ${iface.link} dev ${iface.link} || true
                  counter=$((counter+1))
                done

                echo "Releasing lock"
                exec 4>&-
              '';
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
            })) ethernetLinks) ++


        (let
          unitName = link: "network-disable-ipv6-autoconfig-${link}";
          unitTemplate = link: rec {
            description = "Disable IPv6 autoconfig for link ${link}";
            wantedBy = [ "network-addresses-${link}.service" ];
            before = wantedBy;
            requires = [ "${link}-netdev.service" ];
            after = requires;
            path = [ pkgs.procps fclib.relaxedIp ];
            stopIfChanged = false;
            script = ''
              # Disable IPv6 SLAAC (autoconf)
              sysctl net.ipv6.conf.${link}.accept_ra=0
              sysctl net.ipv6.conf.${link}.autoconf=0
              sysctl net.ipv6.conf.${link}.temp_valid_lft=0
              sysctl net.ipv6.conf.${link}.temp_prefered_lft=0

              # If an interface has previously been managed by dhcpcd this sysctl might be
              # set to a non-zero value, which disables automatic generation of link-local
              # addresses. This can leave the interface without a link-local address when
              # dhcpcd deletes addresses from the interface when it exits. Resetting this
              # to 0 restores the default kernel behaviour.
              sysctl net.ipv6.conf.$IFACE.addr_gen_mode=0

              for oldtmp in `ip -6 address show dev ${link} dynamic scope global | grep inet6 | cut -d ' ' -f6`; do
                ip addr del $oldtmp dev ${link}
              done
            '';
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
          };

          virtualLinkUnit = link: ((unitTemplate link) // {
            bindsTo = [ "${link}-netdev.service" ];
            after = [ "${link}-netdev.service" ];
          });
        in
          (map (link:
            lib.nameValuePair (unitName link) (virtualLinkUnit link))
            virtualLinks)
        ) ++

        (lib.optionals (!isNull fclib.underlay)
          # loopback dummy device
            (let linkName = fclib.underlay.interface; in
          [
            (lib.nameValuePair
            "${linkName}-netdev"
            rec {
              description = "Dummy interface ${linkName}";
              wantedBy = [ "network-setup.service" "multi-user.target" ];
              before = wantedBy;
              after = [ "network-pre.service" ];
              requires = [ "network-setup.service" ];
              path = [ pkgs.nettools pkgs.procps fclib.relaxedIp ];
              reloadIfChanged = true;
              script = ''
                # Create virtual interface underlay
                ip link add ${linkName} type dummy

                ip link set ${linkName} mtu ${toString fclib.network.ul.mtu}
              '';
              reload = ''
                ip link set ${linkName} mtu ${toString fclib.network.ul.mtu}
              '';
              preStop = ''
                ip link delete ${linkName}
              '';
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
            }
          )] ++
          # vxlan kernel devices
          (map (iface: (lib.nameValuePair
            "${iface.link}-netdev"
            rec {
              description = "VXLAN link device ${iface.link}";
              wantedBy = [ "network-setup.service" "multi-user.target" ];
              before = wantedBy;
              requires = [ "network-addresses-${fclib.underlay.interface}.service" "network-setup.service" ];
              # do not order after network-setup.service as we already declare
              # a before= dependency.
              after = [ "network-addresses-${fclib.underlay.interface}.service" "network-pre.target" ];
              reloadIfChanged = true;
              path = [ pkgs.nettools pkgs.procps fclib.relaxedIp ];
              script = ''
                # Create virtual link ${iface.link}
                ip link add ${iface.link} type vxlan \
                  id ${toString iface.vlanId} \
                  local ${fclib.underlay.loopback} \
                  dstport 4789 \
                  nolearning

                # Set MTU and layer 2 address
                ip link set ${iface.link} address ${iface.mac}
                ip link set ${iface.link} mtu ${toString iface.mtu}

                # Do not automatically generate IPv6 link-local address
                ip link set ${iface.link} addrgenmode none
              '';
              reload = ''
                # Set underlay address for virtual interface ${iface.link}.
                # Note that changing the VNI or destination port after the interface
                # has been created is not supported.
                ip link set ${iface.link} type vxlan local ${fclib.underlay.loopback}

                # Set MTU and layer 2 address
                ip link set ${iface.link} address ${iface.mac}
                ip link set ${iface.link} mtu ${toString iface.mtu}

                # Do not automatically generate IPv6 link-local address
                ip link set ${iface.link} addrgenmode none
              '';
              preStop = ''
                ip link delete ${iface.link}
              '';
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
            })) vxlanInterfaces) ++

          # bridge port configuration for vxlan devices. arp/nd
          # suppression is configured separately, so the router role
          # can turn it off.
          # XXX we always make VXLAN ports bridge ports ... this complicates the
          # code a bit.

          (map (iface: (lib.nameValuePair
            "network-bridge-suppress-flooding-${iface.link}"
            {
              description = "Ensure ARP/ND suppression is enabled for bridge port ${iface.link}";
              wantedBy = [ "multi-user.target" ];
              requires = [ "${iface.interface}-netdev.service" ];
              after = [ "${iface.interface}-netdev.service" ];
              stopIfChanged = false;
              path = [ fclib.relaxedIp ];
              script = ''
                ip link set ${iface.link} type bridge_slave neigh_suppress on
              '';
              reload = ''
                ip link set ${iface.link} type bridge_slave neigh_suppress on
              '';
              unitConfig.ReloadPropagatedFrom = [ "${iface.interface}-netdev.service" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
            }
          )) vxlanInterfaces) ++
          (map (iface: (lib.nameValuePair
            "network-bridge-disable-learning-${iface.link}"
            {
              description = "Ensure MAC address learning is disabled for bridge port ${iface.link}";
              wantedBy = [ "multi-user.target" ];
              requires = [ "${iface.interface}-netdev.service" ];
              after = [ "${iface.interface}-netdev.service" ];
              stopIfChanged = false;
              path = [ fclib.relaxedIp ];
              script = ''
                ip link set ${iface.link} type bridge_slave learning off
              '';
              reload = ''
                ip link set ${iface.link} type bridge_slave learning off
              '';
              unitConfig.ReloadPropagatedFrom = [ "${iface.interface}-netdev.service" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
            }
          )) vxlanInterfaces) ++

          # underlay network physical interfaces
          (map (iface: (lib.nameValuePair
            "network-underlay-link-properties-${iface.link}"
            rec {
              description = "Ensure underlay properties for ${iface.link}";
              wantedBy = [ "network-addresses-${iface.link}.service"
                           "multi-user.target" ];
              before = wantedBy;
              requires = [ "${iface.link}-netdev.service" ];
              after = requires;
              path = [ pkgs.procps ];
              script = ''
                sysctl net.ipv4.conf.${iface.link}.rp_filter=0
              '';
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
            }
          )) fclib.underlay.links) ++
          [
            # fallback unreachable routes
            (lib.nameValuePair
              "network-underlay-routing-fallback"
              rec {
                description = "Ensure fallback unreachable route for underlay prefixes";
                wantedBy = [ "network-addresses-${fclib.underlay.interface}.service"
                             "multi-user.target" ];
                before = wantedBy;
                after = [ "${fclib.underlay.interface}-netdev.service" ];
                path = [ fclib.relaxedIp ];
                stopIfChanged = false;
                # https://docs.frrouting.org/en/stable-8.5/zebra.html#administrative-distance
                #
                # Due to how zebra calculates administrative distance
                # for routes learned from the kernel, we need to set a
                # very high metric on these routes (i.e. very low
                # preference) so that routes learned from BGP can
                # override these statically configured routes.
                script = ''
                  ${lib.concatMapStringsSep "\n"
                    (net: "ip route add unreachable " + net + " metric 335544321")
                    fclib.underlay.subnets
                   }
                '';
                preStop = ''
                  ${lib.concatMapStringsSep "\n"
                    (net: "ip route del unreachable " + net + " metric 335544321")
                    fclib.underlay.subnets
                   }
                '';
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                };
              }
            )
            # interface altnames from lldp
            (lib.nameValuePair
              "fc-lldp-to-altnames"
              rec {
                description = "Set interface altnames based on peer hostname advertised in LLDP";
                after = [ "lldpd.service" ];
                unitConfig.Requisite = after;
                serviceConfig.Type = "oneshot";
                script = let
                  links = lib.concatStringsSep " " (map (i: i.link) ethernetLinks);
                in
                  "${pkgs.fc.lldp-to-altname}/bin/fc-lldp-to-altname -q ${links}";
              }
            )
            # ensure that restarts of ul-loopback are propagated to zebra
            # because zebra doesn't correctly recover from this so we need a
            # hard restart.
            (lib.nameValuePair
              "zebra"
              rec {
                requires = [ "network-addresses-${fclib.underlay.interface}.service" ];
                # The default zebra has an after for `network.target` but zebra is itself
                # a network service and this creates a dependency cycle. We really just
                # want the underlay to be there.
                after = lib.mkForce requires;
              }
            )
          ])
        )));

    flyingcircus.services.sensu-client.checks = lib.optionalAttrs (!isNull fclib.underlay) {
      uplink_redundancy = {
        notification = "Host has redundant switch connectivity";
        interval = 600;
        command = let
          links = lib.concatStringsSep " " (map (i: i.link) fclib.underlay.links);
        in
          "/run/wrappers/bin/sudo ${pkgs.fc.check-link-redundancy}/bin/check_link_redundancy ${links}";
      };
      rib_integrity_ipv4 = {
        notification = "Kernel network state has problems with underlay network routes";
        interval = 300;
        command = let
          args = lib.concatMapStringsSep " " (p: "-p " + p) fclib.underlay.subnets;
        in
          "sudo -g frrvty ${pkgs.fc.check-rib-integrity}/bin/check_rib_integrity check-unicast-rib ${args}";
      };
      rib_integrity_evpn = {
        notification = "Kernel network state has broken overlay MAC addresses";
        interval = 300;
        command = let
          args = lib.concatMapStringsSep " " (iface: "-n " + (toString iface.vlanId)) vxlanInterfaces;
        in
          "sudo -g frrvty ${pkgs.fc.check-rib-integrity}/bin/check_rib_integrity check-evpn-rib ${args}";
      };
      # This check is here to identify abysmal but otherwise subtle network speed
      # issues as we have seen in PL-132971. If downloading a 1MiB test file
      # takes longer than 5-10 seconds, something is very much off.
      network_speed = {
        notification = "General network speed";
        command = "check_http -u /rgw-monitoring/probe -H rgw.local -p 7480 -m 1000000:1500000 -w 5 -c 10";
        interval = 7200;
      };
    };

    flyingcircus.passwordlessSudoRules = lib.optionals (!isNull fclib.underlay) [{
      commands = [ "${pkgs.fc.check-link-redundancy}/bin/check_link_redundancy" ];
      groups = [ "sensuclient" ];
    } {
      commands = [ "${pkgs.fc.check-rib-integrity}/bin/check_rib_integrity" ];
      groups = [ "sensuclient" ];
      runAs = ":frrvty";
    }];

    systemd.timers.fc-lldp-to-altnames = lib.mkIf (!isNull fclib.underlay) {
      description = "Timer for updating interface altnames based on peer hostname advertised in LLDP";
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = "*:0/10";
    };

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

      # Ensure we can work in larger VLANs with hundreds of nodes.
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
      "net.core.optmem_max" = "65536";
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

      "net.ipv4.tcp_tw_reuse" = "1";

      # Supposedly this doesn't do much good anymore, but in one of my tests
      # (too many, can't prove right now.) this appeared to have been helpful.
      "net.ipv4.tcp_low_latency" = "1";

      # Optimize multi-path for VXLAN (layer3 in layer3)
      "net.ipv4.fib_multipath_hash_policy" = "2";
    })];

    # Prevent underlay interfaces from matching the rp_filter sysctl
    # glob in the default configuration shipped with systemd.
    environment.etc."sysctl.d/70-fcio-underlay.conf" =
      lib.mkIf (!isNull fclib.underlay) {
        text = lib.concatMapStringsSep "\n"
          (iface: "-net.ipv4.conf.${iface.link}.rp_filter")
          fclib.underlay.links;
      };

  };
}
