# generic networking functions for use in all of the flyingcircus Nix stuff

{ config, pkgs, lib, ... }:

with builtins;
let
  fclib = config.fclib;

  encInterfaces = lib.attrByPath [ "parameters" "interfaces" ] {} config.flyingcircus.enc;

  foldConds = value: conds:
    let
      f = base: elem: if elem.cond then throw elem.fail else base;
    in lib.foldl f value conds;

  interfaceData =
    let
      underlayInterfaces = lib.filterAttrs (name: value: name != "ul" && value.policy == "underlay") encInterfaces;
      underlayCount = length (attrNames underlayInterfaces);
      vxlanInterfaces = lib.filterAttrs (name: value: value.policy == "vxlan") encInterfaces;
      vxlanCount = length (attrNames vxlanInterfaces);
    in
      if config.flyingcircus.infrastructureModule != "flyingcircus-physical"
      then foldConds encInterfaces
        [
          {
            cond = underlayCount > 0;
            fail = "Only physical hosts may have interfaces with policy 'underlay'";
          }
          {
            cond = hasAttr "ul" encInterfaces;
            fail = "Only physical hosts may be connected to the 'ul' network";
          }
          {
            cond = vxlanCount > 0;
            fail = "Only physical hosts may have interfaces with policy 'vxlan'";
          }
        ]
      else foldConds encInterfaces
        [
          {
            cond = underlayCount > 0;
            fail = "Only the 'ul' network may have policy 'underlay'";
          }
          {
            cond = hasAttr "ul" encInterfaces && encInterfaces.ul.policy == "vxlan";
            fail = "The 'ul' network may not have policy 'vxlan'";
          }
          {
            cond = vxlanCount > 0 && (!hasAttr "ul" encInterfaces || encInterfaces.ul.policy != "underlay");
            fail = "VXLAN devices cannot be configured without an underlay interface";
          }
        ];
in
rec {
  stripNetmask = cidr: head (lib.splitString "/" cidr);

  prefixLength = cidr: lib.toInt (elemAt (lib.splitString "/" cidr) 1);
  # The same as prefixLength, but returns a string not an int
  prefix = cidr: elemAt (lib.splitString "/" cidr) 1;

  netmaskFromPrefixLength = prefix:
     (ip4.fromNumber
       (((fclib.pow 2 prefix) - 1) * (fclib.pow 2 (32-prefix)))
       prefix).address;
  netmaskFromCIDR = cidr:
    netmaskFromPrefixLength (prefixLength cidr);

  isIp4 = cidr: length (lib.splitString "." cidr) == 4;
  isIp6 = cidr: length (lib.splitString ":" cidr) > 1;

  # choose correct "iptables" invocation depending on the address
  iptables = a:
    if isIp4 a then "iptables" else
    if isIp6 a then "ip6tables" else
    "ip46tables";

  # choose correct "ip" invocation depending on the address
  ip' = a: "ip " + (if isIp4 a then "-4" else if isIp6 a then "-6" else "");

  fqdn = {vlan,
          domain ? config.networking.domain,
          location ? lib.attrByPath [ "parameters" "location" ] "standalone" config.flyingcircus.enc,
          }:
      "${config.networking.hostName}.${vlan}.${location}.${domain}";

  quoteIPv6Address = addr: if isIp6 addr then "[${addr}]" else addr;

  listServiceAddresses = service:
  (map
    (service: service.address)
    (filter
      (s: s.service == service)
      config.flyingcircus.encServices));

  listServiceIPs = service:
  (lib.flatten
    (map
      (service: service.ips)
      (filter
        (s: s.service == service)
        config.flyingcircus.encServices)));


  # Return service address (string) or null, if no service
  listServiceAddress = service:
    let
      addresses = listServiceAddresses service;
    in
      if addresses == [] then null else head addresses;

  listServiceAddressesWithPort = service: port:
    map
      (address: "${address}:${toString port}")
      (listServiceAddresses config service);

  # VLANS with prio < 100 are generally routable to the outside.
  routingPriorities = {
    fe = 50;
    srv = 60;
    mgm = 90;
  };

  routingPriority = vlan:
    if hasAttr vlan routingPriorities
    then routingPriorities.${vlan}
    else 100;

  # "example.org." -> absolute name; "example" -> relative to $domain
  normalizeDomain = domain: n:
    if lib.hasSuffix "." n
    then lib.removeSuffix "." n
    else "${n}.${domain}";

  # Convert for example "172.22.48.0/22" into "172.22.48.0 255.255.252.0".
  # Note: this is IPv4 only.
  decomposeCIDR = cidr:
    let
      drvname = "cidr-${replaceStrings [ "/" ":" ] [ "_" "-" ] cidr}";
    in
    readFile (pkgs.runCommand drvname {} ''
      ${pkgs.python3.interpreter} > $out <<'_EOF_'
      import ipaddress
      i = ipaddress.ip_interface('${cidr}')
      print('{} {}'.format(i.ip, i.netmask), end="")
      _EOF_
    '');

  # Adapted 'ip' command which says what it is doing and ignores errno 2 (file
  # exists) to make it idempotent.
  relaxedIp = pkgs.writeScriptBin "ip" ''
    #! ${pkgs.stdenv.shell} -e
    echo ip "$@"
    rc=0
    ${pkgs.iproute}/bin/ip "$@" || rc=$?
    if ((rc == 2)); then
      exit 0
    else
      exit $rc
    fi
  '';

  # Taken from
  # https://github.com/LumiGuide/lumi-example/blob/master/nix/lib.nix
  ip4 = rec {
    ip = a : b : c : d : prefixLength : {
      inherit a b c d prefixLength;
      address = "${toString a}.${toString b}.${toString c}.${toString d}";
    };

    toCIDR = addr : "${addr.address}/${toString addr.prefixLength}";
    toNetworkAddress = addr : with addr; { inherit address prefixLength; };
    toNumber = addr : with addr; a * 16777216 + b * 65536 + c * 256 + d;
    fromNumber = addr : prefixLength :
      let
        aBlock = a * 16777216;
        bBlock = b * 65536;
        cBlock = c * 256;
        a      =  addr / 16777216;
        b      = (addr - aBlock) / 65536;
        c      = (addr - aBlock - bBlock) / 256;
        d      =  addr - aBlock - bBlock - cBlock;
      in
        ip a b c d prefixLength;

    fromString = with lib; str :
      let
        splits1 = splitString "." str;
        splits2 = flatten (map (x: splitString "/" x) splits1);

        e = i : toInt (builtins.elemAt splits2 i);
      in
        ip (e 0) (e 1) (e 2) (e 3) (e 4);

    fromIPString = str : prefixLength :
      fromString "${str}/${toString prefixLength}";

    network = addr :
      let
        pfl = addr.prefixLength;
        shiftAmount = fclib.pow 2 (32 - pfl);
      in
        fromNumber ((toNumber addr) / shiftAmount * shiftAmount) pfl;
  };

  networks = with fclib; rec {
    all = config.flyingcircus.encNetworks;

    v4 = filter isIp4 all;
    v6 = filter isIp6 all;
  };

  network = (lib.mapAttrs'
    (vlan: interface:
      lib.nameValuePair vlan (
      let
        priority = routingPriority vlan;
        bridged = interface.bridged;

        mtu = if hasAttr vlan config.flyingcircus.static.mtus
              then config.flyingcircus.static.mtus.${vlan}
              else 1500;
      in with fclib; rec {

        inherit vlan mtu priority bridged;

        vlanId = config.flyingcircus.static.vlanIds.${vlan};

        device = if bridged then bridgedDevice else layer2device;
        attachedDevices = if bridged then [layer2device] else [];
        bridgedDevice = "br${vlan}";
        layer2device =
          if policy == "underlay" then "underlay"
          else if policy == "vxlan" then "vx${vlan}"
          else "eth${vlan}";

        macFallback = "02:00:00:${fclib.byteToHex vlanId}:??:??";
        mac = lib.toLower
                (lib.attrByPath [ "mac" ] macFallback interface);

        policy = interface.policy;

        dualstack = rec {
          # Without netmask
          addresses = map stripNetmask cidrs;
          # Without netmask, V6 quoted in []
          addressesQuoted = map quoteIPv6Address addresses;
          # as cidr
          cidrs = map (attr: "${attr.address}/${toString attr.prefixLength}") attrs;

          networks = attrNames interface.networks;

          # networks as attribute sets of netmask/prefixLength/addresses
          networkAttrs =
            lib.mapAttrsToList
              (network: addresses: {
                network = fclib.stripNetmask network;
                prefixLength = fclib.prefixLength network;
                inherit addresses;
              })
              interface.networks;

          # addresses as attribute sets of address/prefixLength
          attrs = lib.flatten (lib.mapAttrsToList
            (network: addresses:
              let prefix = fclib.prefixLength network;
              in (map (address: { address = address; prefixLength = prefix; }) addresses))
            interface.networks);

          defaultGateways = lib.mapAttrsToList
            (network: gateway: gateway)
            (lib.filterAttrs (network: gateway:
              (length interface.networks.${network} >= 1) && (priority < 100))
              interface.gateways);
        };

        v4 = {
          addresses = filter isIp4 dualstack.addresses;
          cidrs = filter isIp4 dualstack.addresses;
          attrs = filter (attr: isIp4 attr.address) dualstack.attrs;
          networks = filter isIp4 dualstack.networks;
          networkAttrs = filter (n: isIp4 n.network) dualstack.networkAttrs;
          # Select default gateways for all networks that we have a local IP in
          defaultGateways = filter isIp4 dualstack.defaultGateways;
        };

        v6 = {
          addresses = filter isIp6 dualstack.addresses;
          addressesQuoted = filter isIp6 dualstack.addressesQuoted;
          cidrs = filter isIp6 dualstack.addresses;
          attrs = filter (attr: isIp6 attr.address) dualstack.attrs;
          networks = filter isIp6 dualstack.networks;
          networkAttrs = filter (n: isIp6 n.network) dualstack.networkAttrs;
          # Select default gateways for all networks that we have a local IP in
          defaultGateways = filter isIp6 dualstack.defaultGateways;
        };

      }))
    interfaceData //
      # Provide homogenous access to loopback data
      { lo = {
        vlan = "lo";
        dualstack = {
          addresses = [ "127.0.0.1" "::1" ];
          addressesQuoted = [ "127.0.0.1" "[::1]" ];
        };
        v4 = {
          addresses = [ "127.0.0.1" ];
          addressesQuoted = [ "127.0.0.1" ];
        };
        v6 = {
          addresses = [ "::1" ];
          addressesQuoted = [ "[::1]" ];
        };
      }; });

  underlay =
    if !hasAttr "ul" interfaceData ||
       (lib.attrByPath [ "ul" "policy" ] "puppet" interfaceData) != "underlay" ||
       length (lib.attrByPath [ "ul" "nics" ] [] interfaceData) == 0
    then null
    else let
      hostId = lib.attrByPath [ "parameters" "id" ] 0 config.flyingcircus.enc;
      nics = interfaceData.ul.nics;

      abbrName = name:
        lib.concatMapStrings (s: substring 0 2 s) (lib.splitString "/" name);
      abbrMac = mac:
        lib.concatStrings (lib.drop 3 (lib.splitString ":" mac));
      emptyLabels = any (n: n.external_label == "") nics;
      uniqueAbbrs =
        length nics == length (lib.unique (map (n: abbrName n.external_label) nics));

      makeName = if emptyLabels || !uniqueAbbrs
                 then (n: "ethM${abbrMac n.mac}")
                 else (n: "ethL${abbrName n.external_label}");
    in {
      asNumber = 4200000000 + hostId;
      loopback =
        let addrs = network.ul.v4.addresses;
        in if length addrs == 0
           then throw "Underlay network has no address assigned"
           else head addrs;
      subnets = network.ul.v4.networks;
      interfaces = listToAttrs
        (map (n: lib.nameValuePair (makeName n) n.mac) nics);
      mtu = config.flyingcircus.static.mtus.ul or 1500;
    };
}
