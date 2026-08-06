{ lib }:

with lib;

rec {
  static = import ../nixos/platform/static.nix { inherit lib; };
  vlans = static.config.flyingcircus.static.vlanIds;

  testkey = {
    priv = ''
      -----BEGIN OPENSSH PRIVATE KEY-----
      b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
      QyNTUxOQAAACDEL3cs6kZncaVSHZ+DvTMkiohC3j7MP3ad7Jh40Js6twAAAJjFq84bxavO
      GwAAAAtzc2gtZWQyNTUxOQAAACDEL3cs6kZncaVSHZ+DvTMkiohC3j7MP3ad7Jh40Js6tw
      AAAEDbcHXRiL0+aMh1TaEhnXKqjVpOru/jyfW1Zb6ENAGOcsQvdyzqRmdxpVIdn4O9MySK
      iELePsw/dp3smHjQmzq3AAAAEG1hY2llakBta2ctcmF6ZXIBAgMEBQ==
      -----END OPENSSH PRIVATE KEY-----
    '';
    pub = ''
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMQvdyzqRmdxpVIdn4O9MySKiELePsw/dp3smHjQmzq3 testkey@localhost
    '';
  };

  derivePasswordForHost =
    prefix:
    builtins.hashString "sha256" (
      lib.concatStringsSep "/" [
        prefix
        ""
        "machine"
      ]
    );

  # Returns Sensu check command by name.
  # Newlines in the command are removed to avoid breaking the test script.
  sensuCheckCmd =
    machine: checkName:
    lib.replaceStrings [ "\\" "\n" ] [ "" " " ]
      machine.flyingcircus.services.sensu-client.checks.${checkName}.command;

  /*
    Get a basic configuration for a virtual machine

    Parameters:

      id
        Number of the test node in alphabetic order, starting from 1.

        Example: IDs for the following servers would be assigned:

        annetta=1, berta=2, claus=3

        You can also look at the suffix of eth1' MAC using
        server.execute("ip a >&2") to get the ID)

      net.(sto|stb|fe|srv)

        Boolean flag to enable/disable this particular interface. Default fe/srv=true, rest false

      resource_group

        String flag to set resource_group.

      location

        String flag to set location.

      secrets

        Attrset to provide extra secrets.

    Example usage:
      {
        imports = [
          (testlib.fcConfig {
            id = 1;
            net.fe = false; net.stb = true;
            secrets."test" = "test";
          })
        ]
      }
  */

  fcConfig =
    {
      id ? 1,
      net ? { },
      resource_group ? "test",
      location ? "test",
      secrets ? { },
      extraEncParameters ? { },
    }:
    {
      lib,
      config,
      nodes,
      ...
    }:
    let
      fclib = config.fclib;

      # This is a dance around enabling/disabling and defining defaults of
      # which VLANs/interface to enable in a test that can be overriden.
      network_options = mapAttrs (name: val: false) vlans;
      chosen_networks = (
        network_options
        // {
          srv = true;
          fe = true;
        }
        // net
      );
      active_vlan_attrs = filterAttrs (name: vid: chosen_networks.${name}) vlans;

      # the nixos test driver internally assigns each test vm an id
      # which is used for generating the mac addresses on each
      # vlan. however, this might be a different id from the one we use
      # for generating ip addresses.
      test_node_id = config.virtualisation.test.nodeNumber;

      # Set options in the test harness to indicate our "primary" IP
      # addresses. Take the first v4/v6 addresses from FE, otherwise
      # falling back to SRV if configured.
      primaryAddresses =
        let
          ifaces = config.flyingcircus.enc.parameters.interfaces;
          iface = ifaces.fe or ifaces.srv or null;

          networks = if iface == null then [ ] else attrsToList (iface.networks);
          networksV4 = filter (net: fclib.isIp4 net.name) networks;
          networksV6 = filter (net: fclib.isIp6 net.name) networks;

          primaryAddr =
            nets:
            if nets == [ ] then
              null
            else
              let
                net = head nets;
              in
              if net.value == [ ] then null else head net.value;
        in
        {
          v4 = primaryAddr networksV4;
          v6 = primaryAddr networksV6;
        };

      # Read the configs of other VMs in this test to configure the
      # hosts file.
      hostEntries =
        let
          go =
            prev: name: cfg:
            let
              host =
                (lib.optionalString (
                  cfg.networking.domain != null
                ) "${cfg.networking.hostName}.${cfg.networking.domain} ")
                + "${cfg.networking.hostName}";

            in
            lib.foldr (hself: hprev: if hself == "" then hprev else [ "${hself} ${host}" ] ++ hprev) prev [
              cfg.networking.primaryIPAddress
              cfg.networking.primaryIPv6Address
            ];
        in
        lib.foldlAttrs go [ ] nodes;

      # XXX: srv interfaces are missing (PL-134248)
      extraHosts = lib.concatStringsSep "\n" hostEntries;
    in
    {
      imports = [
        ../nixos
        ../nixos/roles
      ];

      config = {

        users.users.s-test = {
          isNormalUser = true;
          extraGroups = [ "service" ];
        };

        virtualisation.interfaces = fcVlanIfaces (
          listToAttrs (
            map (vlan: nameValuePair vlan vlans.${vlan}) (
              attrNames config.flyingcircus.enc.parameters.interfaces
            )
          )
        );

        networking = {
          inherit extraHosts;

          domain = fclib.mkPlatform "example.local";

          primaryIPAddress = fclib.mkOverrideUpstreamModule (
            lib.optionalString (primaryAddresses.v4 != null) primaryAddresses.v4
          );
          primaryIPv6Address = fclib.mkOverrideUpstreamModule (
            lib.optionalString (primaryAddresses.v4 != null) primaryAddresses.v6
          );
        };

        flyingcircus.enc.parameters = (
          lib.recursiveUpdate {
            inherit resource_group location secrets;

            memory = config.virtualisation.memorySize;
            interfaces = mapAttrs (name: vid: {
              mac = "52:54:00:12:0${toString vid}:0${toString test_node_id}";
              bridged = false;
              linktype = "bridged";
              networks = {
                "192.168.${toString vid}.0/24" = [ "192.168.${toString vid}.${toString id}" ];
                "2001:db8:${toString vid}::/64" = [ "2001:db8:${toString vid}::${toString id}" ];
              };
              gateways = { };
              nics = [
                {
                  "mac" = "52:54:00:12:0${toString vid}:0${toString test_node_id}";
                  "external_label" = "${name}nic${toString id}";
                }
              ];
            }) active_vlan_attrs;
          } extraEncParameters
        );
      };
    };

  # Generate a machine configuration which mocks a datacentre VXLAN switch
  mockVxlanSwitch =
    {
      id,
      links ? [ ],
    }:
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      vlanInterfaces = listToAttrs (map (v: lib.nameValuePair "eth${toString v}" v) links);
      underlayAddress = "192.168.${toString vlans.ul}.${toString id}";
    in
    {
      imports = [
        ../nixos
        ../nixos/roles
      ];
      services.telegraf.enable = false;
      networking = {
        useDHCP = lib.mkForce false;
        firewall.allowPing = lib.mkForce true;
        firewall.checkReversePath = lib.mkForce false;
      };
      boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = lib.mkForce 1;
      boot.initrd.availableKernelModules = [ "dummy" ];
      networking.firewall.enable = false;

      virtualisation.vlans = lib.mkForce [ ];
      virtualisation.interfaces = mapAttrs (_: vlan: { inherit vlan; }) vlanInterfaces;

      networking.firewall.trustedInterfaces = attrNames vlanInterfaces;
      networking.interfaces = {
        underlay.ipv4.addresses = [
          {
            address = underlayAddress;
            prefixLength = 32;
          }
        ];
      }
      // (listToAttrs (
        map (
          name:
          lib.nameValuePair name {
            ipv4.addresses = lib.mkForce [ ];
            ipv6.addresses = lib.mkForce [ ];
          }
        ) (attrNames vlanInterfaces)
      ));

      systemd.services = {
        underlay-netdev = rec {
          description = "Set up underlay loopback device";
          wantedBy = [
            "network-setup.service"
            "multi-user.target"
          ];
          before = wantedBy;
          after = [ "network-pre.service" ];
          requires = [ "network-setup.service" ];
          path = [ pkgs.iproute2 ];
          script = "ip link add underlay type dummy";
          preStop = "ip link delete underlay";
          serviceConfig.Type = "oneshot";
          serviceConfig.RemainAfterExit = true;
        };
      }
      // (listToAttrs (
        map (
          name:
          lib.nameValuePair "${name}-netdev" {
            wantedBy = [
              "network-setup.service"
              "multi-user.target"
            ];
            requires = [ "network-setup.service" ];
            script = ":";
            serviceConfig.Type = "oneshot";
            serviceConfig.RemainAfterExit = true;
          }
        ) (attrNames vlanInterfaces)
      )

      );

      # udev in the test vm initrd sometimes run before hardware
      # enumeration completes.
      services.udev.extraRules = config.boot.initrd.services.udev.rules;

      services.frr = {
        bfdd.enable = true;
        bgpd.enable = true;
        config = ''
          frr version 8.5.1
          frr defaults datacenter
          !
          router bgp ${toString (65000 + id)}
           bgp router-id ${underlayAddress}
           bgp bestpath as-path multipath-relax
           no bgp ebgp-requires-policy
           neighbor remotes peer-group
           neighbor remotes remote-as external
           neighbor remotes capability extended-nexthop
           neighbor remotes passive
           neighbor remotes bfd
           ${lib.concatMapStringsSep "\n " (name: "neighbor ${name} interface peer-group remotes") (
             attrNames vlanInterfaces
           )}
           !
           address-family ipv4 unicast
            redistribute connected
            neighbor remotes route-map accept-all-routes in
            neighbor remotes route-map accept-all-routes out
           exit-address-family
           !
           address-family l2vpn evpn
            neighbor remotes activate
            neighbor remotes route-map accept-all-routes in
            neighbor remotes route-map accept-all-routes out
            advertise-all-vni
            advertise-svi-ip
           exit-address-family
          !
          exit
          !
          route-map accept-all-routes permit 1
          exit
          !
          route-map set-source-address permit 1
           set src ${underlayAddress}
          exit
          !
          ip protocol bgp route-map set-source-address
          !
        '';
      };
    };

  fcVlanIfaces = mapAttrs' (
    vlan: vid: {
      name = "eth${vlan}";
      value = {
        vlan = vid;
        assignIP = false;
      };
    }
  );

  fcIPMap = listToAttrs (
    concatLists (
      mapAttrsToList (name: vid: [
        (nameValuePair "${name}4" {
          quote = false;
          prefix = "192.168.${toString vid}.";
        })
        (nameValuePair "${name}6" {
          quote = true;
          prefix = "2001:db8:${toString vid}::";
        })
      ]) vlans
    )
  );

  /*
    Get IP from server id
    Examples:
      fcIP.srv6 1 -> "2001:db8:3::1"
      fcIP.quote.srv6 -> "[2001:db8:3::1]"
  */
  fcIP = (mapAttrs (type: typeconf: (id: "${typeconf.prefix}${toString id}")) fcIPMap) // {
    quote = mapAttrs (
      type: typeconf: id:
      if typeconf.quote then "[${typeconf.prefix}${toString id}]" else "${typeconf.prefix}${toString id}"
    ) fcIPMap;
  };

}
