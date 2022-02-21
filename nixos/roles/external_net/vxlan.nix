# Gateway to external network via VxLAN tunnel.

# HOT TO SET UP DNS
# (1) Set up a specific FQDN for the FE address(es) of the gateway machine.
# (2) Set up a NS record that installs this FQDN as the authoritative nameserver
# for the ext domain.
# Example:
# vxlan.test.fcio.net.  CNAME test31.fe
# ext.test.fcio.net.    NS    vxlan.test.fcio.net.

{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  cfg = config.flyingcircus;
  vxlanRole = config.flyingcircus.roles.vxlan;
  extnet = cfg.roles.external_net;
  parameters = lib.attrByPath [ "enc" "parameters" ] {} cfg;
  interfaces = lib.attrByPath [ "interfaces" ] {} parameters;
  resource_group = lib.attrByPath [ "resource_group" ] null parameters;

  net4 = extnet.vxlan4;
  net6 = extnet.vxlan6;
  dev = "nx0";
  realdev = "ethfe";
  port = 8472;

  exampleConfig = ''
    {
      "local": "2001:db8:62::118d",
      "remote": "2001:db0:ff::30d",
      "vid": 2,
      "mtu": 1430
    }
  '';

  jsonConfig = (fromJSON
    (fclib.configFromFile /etc/local/vxlan/config.json "{}"));

    # Compute all necessary parameters with Python and funnel them into Nix
    # via JSON marshalling. You could call this a hack.
    params = fromJSON (readFile (
      pkgs.stdenv.mkDerivation {
        name = "vxlan-network-params.json";
        # expects net4 and net6 as command line arguments, returns a JSON
        # containg all kinds of VxLAN/dnsmasq addresses/networks
        script = ''
          import json
          import ipaddress
          import sys
          net4, net6 = sys.argv[1:]
          ip4 = ipaddress.ip_network(net4)
          ip6 = ipaddress.ip_network(net6)
          print(json.dumps({
            'a': str(ip4[1]),
            'aaaa': str(ip6[1]),
            'gw4': '{}/{}'.format(ip4[1], ip4.prefixlen),
            'gw6': '{}/{}'.format(ip6[1], ip6.prefixlen),
            'dhcp': (str(ip4[2]), str(ip4[-1])),
          }))
        '';
        passAsFile = [ "script" ];
        buildCommand = ''
          ${pkgs.python3.interpreter} $scriptPath ${net4} ${net6} > $out
        '';
      }).out);

    mtu = lib.attrByPath [ "mtu" ] 1430 vxlanRole.config;

    domain =
      if resource_group != null
      then "${resource_group}.fcio.net"
      else "local";

    feAddrs = fclib.network.fe.dualstack.addresses;
    fqdn = "${config.networking.hostName}.ext.${domain}";

    dnsmasqConf = ''
      # VXLan specific configuration
      dhcp-authoritative
      dhcp-fqdn
      dhcp-option=option6:dns-server,[::]
      dhcp-option=option6:ntp-server,[::]
      dhcp-option=option:dns-server,0.0.0.0
      dhcp-option=option:mtu,${toString mtu}
      dhcp-option=option:ntp-server,0.0.0.0
      dhcp-range=::,constructor:${dev},ra-names
      dhcp-range=${lib.concatStringsSep "," params.dhcp},24h
      domain=ext.${domain}
      domain-needed
      interface=lo,${dev}
      except-interface=ethfe
      except-interface=ethsrv
      local-ttl=60
      auth-server=${extnet.frontendName},ethfe
      auth-zone=ext.${domain}
      host-record=${fqdn},${params.a},${params.aaaa}
    '';

in
{
  options = with lib; {
    flyingcircus.roles.vxlan =  {
      gateway = mkEnableOption { };

      supportsContainers = fclib.mkDisableContainerSupport;

      config = mkOption {
        type = types.attrs;
        default = jsonConfig;
        description = ''
          Set containing the parameters needed for setting up the VxLAN tunnel.
          If nothing is specified here, the config is loaded from /etc/local/vxlan/config.json.
          See /etc/local/vxlan/config.json.example for required parameters.
        '';
      };
    };
  };

  config = lib.mkMerge [

    # vxlan service is only loaded if config is present
    (lib.mkIf (cfg.roles.vxlan.gateway && vxlanRole.config != {}) {
      services.dnsmasq = {
        enable = true;
        extraConfig = dnsmasqConf;
      };

      services.chrony.extraConfig = ''
        allow ${net4}
        allow ${net6}
      '';
      # See default.nix and openvpn.nix for additional firewall rules
      networking.firewall.allowedUDPPorts = [ 67 68 123 port ];

      systemd.services."vxlan-${dev}" = rec {
        description = "VxLAN tunnel ${dev}";
        after = [ "network-addresses-${realdev}.service" ];
        wantedBy = [ "dnsmasq.service" ];
        before = wantedBy;
        bindsTo = [ "sys-subsystem-net-devices-${realdev}.device" ];

        serviceConfig = let
          ip = "${pkgs.iproute}/bin/ip";
          inherit (params) gw4 gw6;
          inherit (vxlanRole.config) vid remote local;
        in {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeScript "vxlan-${dev}-start" ''
            #!${pkgs.stdenv.shell} -e
            echo "adding link ${dev}"
            ${ip} link del ${dev} 2>/dev/null || true
            ${ip} link add ${dev} type vxlan id ${toString vid} \
              dev ${realdev} local ${local} remote ${remote} \
              dstport ${toString port}
            ${ip} link set up mtu ${toString mtu} dev ${dev}
            ${ip} -4 addr add ${gw4} dev ${dev}
            ${ip} -6 addr add ${gw6} dev ${dev}
          '';
          ExecStop = pkgs.writeScript "vxlan-${dev}-stop" ''
            #!${pkgs.stdenv.shell} -e
            echo "removing link ${dev}"
            ${ip} link set ${dev} down
            ${ip} link del ${dev}
          '';
        };
      };
    })

    (lib.mkIf cfg.roles.vxlan.gateway {
      environment.etc."local/vxlan/config.json.example".text = exampleConfig;
      environment.etc."local/vxlan/README.txt".text = readFile ./README.vxlan;
    })
  ];
}
