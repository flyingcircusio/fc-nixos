# Managed external network (OpenVPN/DHP/...) gateway
{ lib, config, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  cfg = config.flyingcircus;
  parameters = lib.attrByPath [ "enc" "parameters" ] {} cfg;

  # attrset of those fe addresses that have a reverse
  feReverses =
    # fake attrset from listenAddresses: { "addr" = null; ... }
    let feAddrSet =
      lib.genAttrs (fclib.listenAddresses "ethfe") (x: null);
    in
    intersectAttrs feAddrSet (lib.attrByPath [ "reverses" ] {} parameters);

  # pick a suitable DNS name for client config
  domain = config.networking.domain;
  defaultFrontendName =
    if feReverses != {}
    then fclib.normalizeDomain domain (head (attrValues feReverses))
    else fclib.feFQDN;

in
{
  imports = [
    ./openvpn.nix
    ./vxlan.nix
    ./vxlan-client.nix
  ];

  options = {
    flyingcircus.roles.external_net = {

      enable = lib.mkEnableOption { };

      vxlan4 = lib.mkOption {
        type = lib.types.str;
        default = "10.102.99.0/24";
        description = ''
          IPv4 network range for VxLAN external network. Must be changed on all
          nodes within a RG for end-to-end routing. So it is best to leave it
          alone.
        '';
      };

      vxlan6 = lib.mkOption {
        type = lib.types.str;
        default = "fd3e:65c4:fc10:fc::/64";
        description = ''
          IPv6 network range for VxLAN external network. Must be changed on all
          nodes within a RG for end-to-end routing. So it is best to leave it
          alone.
        '';
      };

      frontendName = lib.mkOption {
        type = lib.types.str;
        default = defaultFrontendName;
        description = ''
          DNS host name for the external network gateway. This is also the name
          of the OpenVPN client configuration. The default is derived from the
          FE address' reverse name.
        '';
      };

    };
  };

  config = lib.mkIf cfg.roles.external_net.enable {
    # does not interact well with old-style policy routing
    flyingcircus.network.policyRouting.enable = lib.mkForce false;

    flyingcircus.roles.openvpn.enable = true;

    flyingcircus.roles.vxlan.gateway = true;

    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.ipv6.conf.default.forwarding" = 1;
    };

    environment.systemPackages = [ pkgs.mosh ];

    # we need 53/udp in any case, both openvpn and vxlan use dnsmasq
    # 60000-60003 is for mosh
    networking.firewall.allowedUDPPorts = [ 53 60000 60001 60002 60003 ];
  };
}
