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
      underlayInterfaces = lib.filterAttrs (name: value: name != "ul" && value.policy or null == "underlay") encInterfaces;
      underlayCount = length (attrNames underlayInterfaces);
      vxlanInterfaces = lib.filterAttrs (name: value: value.policy or null == "vxlan") encInterfaces;
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

  underlayLoopbackLinkName = "ul-loopback";

  buildComplexInterfaceName = prefix: label: let
    splitLabel = split "[^a-z0-9]" label;
    parts = filter isString splitLabel;
    dashes = length (filter (p: ! (isString p)) splitLabel);
    prefixLen = stringLength prefix;
    partsLen = length parts;
    namebytes =
      # Canonical interface names must be at most 16 bytes in length,
      # *including* the trailing null byte(!). The fixed prefix "ul-"
      # is three bytes long, and name fragments are separated by
      # dashes.
      assert (partsLen + dashes + prefixLen) < 16;
      # There's an off by one down there which does end up with
      # 16 characters sometimes ...
      # e.g. "eth-onboard-left"
      15 - dashes - prefixLen;

    stringListLength = lib.foldl (a: b: a + (stringLength b)) 0;

    go = item: state: let
      capacity = namebytes - (stringListLength state);
      remaining = partsLen - (length state);
      prefixBaseLen = capacity / remaining;
      moduloOffset =
        if (lib.mod capacity remaining) >= (length state)
        then 1 else 0;

      prefixLength = prefixBaseLen + moduloOffset;
    in [(lib.substring 0 prefixLength item)] ++ state;

    builder = lib.foldr go [] parts;
  in prefix + (lib.concatStringsSep "-" builder);

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
    echo ip "$@" >&2
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
    (vlan: interface':
      lib.nameValuePair vlan (
      let
        priority = routingPriority vlan;
        bridged = interface'.bridged || interface'.policy or null == "vxlan";

        mtu = if hasAttr vlan config.flyingcircus.static.mtus
              then config.flyingcircus.static.mtus.${vlan}
              else 1500;
      in with fclib; rec {

        inherit vlan mtu priority bridged;

        vlanId = config.flyingcircus.static.vlanIds.${vlan};

        # Our nomenclature:
        #
        # An `interface` is the thing that we configure IP addresses on. It's
        # mostly layer 3 oriented.
        #
        # A `link` is a thing that carries a MAC address and provides a physical
        # or virtual connection to the network that IP can run on. It's mostly
        # layer 2 oriented.
        #
        # We explicitly do not follow a strict OSI model here, as the model
        # just doesn't correspond well with reality:
        #
        # Interfaces know which network segment they belong to (the VLAN)
        # and may indicate that they want to run `tagged` on their associated
        # link.
        #
        # We do not fully model the stack of `links` that make up the
        # `interface` but the `link` part is responsible for setting up things
        # like bridges.
        #
        # The challenge here is, that this code needs to "marry" the two concepts:
        # IP addresses are assigned to kernel objects that have conflicting
        # conceptual names: sometimes they are called `links`, sometimes
        # `devices`, or `interfaces`. Our variables here need to help us
        # understand this.
        #
        # The general stacking order is:
        #
        #   link [-> taggedLink (decapsulated) ] [-> bridgedLink]
        #
        # Examples:
        #
        # Untagged, unbridged:
        #         ethsrv (link and taggedLink and interface)
        #
        # Untagged, bridged:
        #         ethsrv (link and taggedLink)
        #         brsrv (interface and bridgedLink)
        #
        # Tagged, unbridged:
        #         ethextleft (link)
        #         ethsrv (interface and taggedLink)
        #
        # Tagged, bridged:
        #         ethextleft (link)
        #         ethsrv (taggedLink)
        #         brsrv (interface and bridgedLink)

        # interface: the kernel object that we assign the IP addresses for this
        # ... well ... interface
        interface =
          if bridged then bridgedLink
          else if policy == "tagged" then taggedLink
          else link;

        attachedLinks = if bridged then [link] else [];
        bridgedLink = "br${vlan}";  # the kernel device with type `bridge`
        taggedLink = "eth${vlan}";  # the kernel device with type `vlan`

        # The basic link that provides connectivity to the outside world.
        # In simple cases this can be the plain physical ethernet device/
        # interface like `ethmgm` or `ethmgm`.
        # Depending on the policy this can be a more indirect object like
        # the underlay loopback device.
        link =
          if policy == "underlay" then underlayLoopbackLinkName
          else if policy == "vxlan" then "vx${vlan}"
          else if policy == "tagged" then "${buildComplexInterfaceName "eth-" (builtins.head interface'.nics).external_label or "vlan"}"
          else taggedLink;

        externalLabel = if (length (interface'.nics or 0) > 0) then (builtins.head interface'.nics).external_label else null;

        linkStack = lib.unique (filter (l: l != null) [
          link
          (if (policy == "underlay") then underlayLoopbackLinkName else null)
          (if (policy == "tagged") then taggedLink else null)
          interface
        ]);

        macFallback = "02:00:00:${fclib.byteToHex vlanId}:??:??";
        mac = lib.toLower
                (lib.attrByPath [ "mac" ] macFallback interface');

        policy = interface'.policy or "puppet";

        dualstack = rec {
          # Without netmask
          addresses = map stripNetmask cidrs;
          # Without netmask, V6 quoted in []
          addressesQuoted = map quoteIPv6Address addresses;
          # as cidr
          cidrs = map (attr: "${attr.address}/${toString attr.prefixLength}") attrs;

          networks = attrNames interface'.networks;

          # networks as attribute sets of netmask/prefixLength/addresses
          networkAttrs =
            lib.mapAttrsToList
              (network: addresses: {
                network = fclib.stripNetmask network;
                prefixLength = fclib.prefixLength network;
                inherit addresses;
              })
              interface'.networks;

          # addresses as attribute sets of address/prefixLength
          attrs = lib.flatten (lib.mapAttrsToList
            (network: addresses:
              let prefix = fclib.prefixLength network;
              in (map (address: { address = address; prefixLength = prefix; }) addresses))
            interface'.networks);

          defaultGateways = lib.mapAttrsToList
            (network: gateway: gateway)
            (lib.filterAttrs (network: gateway:
              (length interface'.networks.${network} >= 1) && (priority < 100))
              interface'.gateways);
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
       # XXX the directory should switch to the `links` nomenclature
       length (lib.attrByPath [ "ul" "nics" ] [] interfaceData) == 0
    then null
    else let
      hostId = lib.attrByPath [ "parameters" "id" ] 0 config.flyingcircus.enc;
      links = interfaceData.ul.nics; # xxx directory should rename this field

      underlayLinkName = buildComplexInterfaceName "ul-";

      underlayMacFallback = mac: let
        digits = lib.drop 3 (lib.splitString ":" mac);
      in "ul-mac-" + (lib.concatStrings digits);

      emptyLabels = any (l: l.external_label == "") links;
      uniqueNames =
        length links ==
          length (lib.unique (map (l: underlayLinkName l.external_label) links));

      makeName = if emptyLabels || !uniqueNames
                 then (l: underlayMacFallback l.mac)
                 else (l: underlayLinkName l.external_label);
    in {
      asNumber = 4200000000 + hostId;
      loopback =
        let addrs = network.ul.v4.addresses;
        in if length addrs == 0
           then throw "Underlay network has no address assigned"
           else head addrs;
      interface = underlayLoopbackLinkName;
      subnets = network.ul.v4.networks;
      links = map (l: {
          # Unify with the fclib.network. structure
          mac = l.mac;
          mtu = network.ul.mtu;
          interface = underlayLoopbackLinkName;
          link = (makeName l);
          externalLabel = l.external_label;
        }) links;
    };
}
