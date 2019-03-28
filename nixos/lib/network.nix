# generic networking functions for use in all of the flyingcircus Nix stuff

{ pkgs, lib, ... }:

with builtins;

rec {
  stripNetmask = cidr: head (lib.splitString "/" cidr);

  prefixLength = cidr: lib.toInt (elemAt (lib.splitString "/" cidr) 1);

  # The same as prefixLength, but returns a string not an int
  prefix = cidr: elemAt (lib.splitString "/" cidr) 1;

  isIp4 = cidr: length (lib.splitString "." cidr) == 4;

  isIp6 = cidr: length (lib.splitString ":" cidr) > 1;

  # choose correct "iptables" invocation depending on the address
  iptables = a:
    if isIp4 a then "iptables" else
    if isIp6 a then "ip6tables" else
    "ip46tables";

  # choose correct "ip" invocation depending on the address
  ip' = a: "ip " + (if isIp4 a then "-4" else if isIp6 a then "-6" else "");

  # list IP addresses for service configuration (e.g. nginx)
  listenAddresses = config: interface:
    if interface == "lo"
    # lo isn't part of the enc. Hard code it here.
    then [ "127.0.0.1" "::1" ]
    else
      if hasAttr interface config.networking.interfaces
      then
        let
          interface_config = getAttr interface config.networking.interfaces;
        in
          (map (addr: addr.address) interface_config.ipv4.addresses) ++
          (map (addr: addr.address) interface_config.ipv6.addresses)
      else [];

  listenAddressesQuotedV6 = config: interface:
    map
      (addr:
        if isIp6 addr then
          "[${addr}]"
        else addr)
      (listenAddresses config interface);

  listServiceAddresses = config: service:
  (map
    (service: service.address)
    (filter
      (s: s.service == service)
      config.flyingcircus.encServices));

  listServiceIPs = config: service:
  (lib.flatten
    (map
      (service: service.ips)
      (filter
        (s: s.service == service)
        config.flyingcircus.encServices)));


  # Return service address (string) or null, if no service
  listServiceAddress = config: service:
    let
      addresses = listServiceAddresses config service;
    in
      if addresses == [] then null else head addresses;

  listServiceAddressesWithPort = config: service: port:
    map
      (address: "${address}:${toString port}")
      (listServiceAddresses config service);

  # Generate "listen" statements for nginx.conf for all IPs
  # of the given interface with modifications.
  # E.g. nginxListenOn config ethfe "443 ssl http2"
  # NOTE: "mod" *must* must start with the port number.
  nginxListenOn  = config: interface: mod:
    lib.concatMapStringsSep "\n  "
      (addr: "listen ${addr}:${toString mod};")
      (listenAddressesQuotedV6 config interface);


  /*
   * policy routing
   */

  dev = vlan: bridged: if bridged then "br${vlan}" else "eth${vlan}";

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

  # transforms ENC "networks" data structure into an NixOS "interface" option
  # for all nets that satisfy `pred`
  # {
  #   "172.30.3.0/24" = [ "172.30.3.66" ... ];
  #   ...;
  # }
  # =>
  # [ { address = "172.30.3.66"; prefixLength = "24"; } ... ];
  ipAddressesOption = pred: networks:
    let
      transformAddrs = net: addrs:
        map
          (a: { address = a; prefixLength = prefixLength net; })
          addrs;
      relevantNetworks = lib.filterAttrs (net: val: pred net) networks;
    in
    lib.concatMap
      (n: transformAddrs n networks.${n})
      (attrNames relevantNetworks);

  # ENC networks to NixOS option for both address families
  interfaceConfig = networks:
    { ipv4.addresses = ipAddressesOption isIp4 networks;
      ipv6.addresses = ipAddressesOption isIp6 networks;
    };

  # Collects a complete list of configured addresses from all networks.
  # Each address is suffixed with the netmask from its network.
  allInterfaceAddresses = networks:
    let
      addrsWithNetmask = net: addrs:
        let p = prefix net;
        in map (addr: addr + "/" + p) addrs;
    in lib.concatLists (lib.mapAttrsToList addrsWithNetmask networks);

  # IP policy rules for a single VLAN.
  # Expects a VLAN name and an ENC "interfaces" data structure. Expected keys:
  # mac, networks, bridged, gateways.
  ipRules = vlan: encInterface: filteredNets: verb:
    let
      prio = routingPriority vlan;
      common = "table ${vlan} priority ${toString prio}";
      fromRules = lib.concatMapStringsSep "\n"
        (a: "${ip' a} rule ${verb} from ${a} ${common}")
        (allInterfaceAddresses encInterface.networks);
      toRules = lib.concatMapStringsSep "\n"
        (n: "${ip' n} rule ${verb} to ${n} ${common}")
        filteredNets;
    in
    "\n# policy rules for ${vlan}\n${fromRules}\n${toRules}\n";

  # A list of default gateways from a list of networks in CIDR form.
  gateways = encIface: filteredNets:
    let
      # don't generate default routes via networks that have no local addresses
      netsWithLocalAddrs = nets:
        filter
          (n: encIface.networks ? ${n} && length encIface.networks.${n} > 0)
          nets;
    in
    foldl'
      (acc: cidr:
        if hasAttr cidr encIface.gateways
        then acc ++ [encIface.gateways.${cidr}]
        else acc)
      []
      (netsWithLocalAddrs filteredNets);

  # Routes for an individual VLAN on an interface. This falls apart into two
  # blocks: (1) subnet routes for all subnets on which the interface has at
  # least one address configured; (2) gateway (default) routes for each subnet
  # where any subnet of the same AF has at least one address.
  ipRoutes = vlan: encInterface: filteredNets: verb:
    let
      prio = routingPriority vlan;
      dev' = dev vlan encInterface.bridged;

      networkRoutesStr = lib.concatMapStrings
        (net: ''
          ${ip' net} route ${verb} ${net} dev ${dev'} metric ${toString prio} table ${vlan}
        '')
        filteredNets;

      common = "dev ${dev'} metric ${toString prio}";
      gatewayRoutesStr = lib.optionalString
        (100 > routingPriority vlan)
        (lib.concatMapStrings
          (gw:
          ''
            ${ip' gw} route ${verb} default via ${gw} ${common}
            ${ip' gw} route ${verb} default via ${gw} ${common} table ${vlan}
          '')
          (gateways encInterface filteredNets));
    in
    "\n# routes for ${vlan}\n${networkRoutesStr}${gatewayRoutesStr}";

  # Format additional routes passed by the 'extraRoutes' parameter.
  ipExtraRoutes = vlan: routes: verb:
    lib.concatMapStringsSep "\n"
      (route:
        let
          a = head (lib.splitString " " route);
        in
        "${ip' a} route ${verb} ${route} table ${vlan}")
      routes;

  # List of nets (CIDR) that have at least one address present which satisfies
  # `predicate`.
  networksWithAtLeastOneAddress = encNetworks: predicate:
    if (lib.any predicate (allInterfaceAddresses encNetworks))
    then filter predicate (lib.attrNames encNetworks)
    else [];

  # For each predicate (AF selector): collect nets (CIDR) in the ENC networks
  # whose AF is represented by at least one address (but not necessarily in the
  # same subnet).
  # Example: Assume two IPv4 networks A, B on an interface where A has an
  # address => then both networks are collected. But when none of the networks
  # has an address configured, no net is collected.
  # Returns the union of all nets which match this criterion for at least one AF
  # predicate present in the second argument.
  filterNetworks = encNetworks: predicates:
    lib.concatMap (networksWithAtLeastOneAddress encNetworks) predicates;

  policyRouting =
    { vlan
    , encInterface
    , action ? "start"  # or "stop"
    , extraRoutes ? [ ]
    }:
    let
      verb = if action == "start" then "add" else "del";
      filteredNets = filterNetworks encInterface.networks [ isIp4 isIp6 ];
    in
    if action == "start"
    then ''
      ${ipRules vlan encInterface filteredNets verb}
      ${ipRoutes vlan encInterface filteredNets verb}
      ${ipExtraRoutes vlan extraRoutes verb}
    '' else ''
      ${ipExtraRoutes vlan extraRoutes verb}
      ${ipRoutes vlan encInterface filteredNets verb}
      ${ipRules vlan encInterface filteredNets verb}
    '';

  simpleRouting =
    { vlan
    , encInterface
    , action ? "start"}:  # or "stop"
    let
      verb = if action == "start" then "add" else "del";
      filteredNets = filterNetworks encInterface.networks [ isIp4 isIp6 ];
      prio = routingPriority vlan;
      dev' = dev vlan encInterface.bridged;
      common = "dev ${dev'} metric ${toString prio}";

      # additional network routes for nets in which we don't have an address
      networkRoutesStr =
        let
          nets = filter (net: encInterface.networks.${net} == []) filteredNets;
        in
        lib.concatMapStrings
          (net: ''
            ${ip' net} route ${verb} ${net} dev ${dev'} metric ${toString prio}
          '')
          nets;

      # gateway routes only for nets in which we do have an address
      gatewayRoutesStr =
        let
          nets = filter (net: encInterface.networks.${net} != []) filteredNets;
        in
        lib.optionalString
          (100 > routingPriority vlan)
          (lib.concatMapStrings
            (gw: "${ip' gw} route ${verb} default via ${gw} ${common}\n")
            (gateways encInterface nets));
    in
    "\n# routes for ${vlan}\n${networkRoutesStr}${gatewayRoutesStr}";

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

}
