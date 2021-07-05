# Access external networks like VxLAN tunnels to Kamp DHP.
# The role activates itself if an appropriate ENC service is present and the host isn't a VxLAN gateway.

{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus;
  fclib = config.fclib;
  gw = lib.findFirst
    (s: s.service == "external_net-gateway") null cfg.enc_services;
  fqdn = "${cfg.enc.name}.${config.networking.domain}";
in

{
  options = {
    flyingcircus.roles.external_net_client = {
      enable = lib.mkOption {
        description = "Access external networks via external_net gateway";
        type = lib.types.bool;
        default = (gw != null) && (!cfg.roles.vxlan.gateway);
      };
    };
  };

  config = lib.mkIf cfg.roles.external_net_client.enable (
    let
      gwHost = gw.address;
      gwIp4 = toString (filter fclib.isIp4 gw.ips);
      gwIp6 = toString (filter fclib.isIp6 gw.ips);
      extnet = cfg.roles.external_net;
    in
    {
      systemd.services."network-external-routing" = 
        let 
          netdev = fclib.network.srv.device;
        in rec {
        description = "Custom routing rules dsafds for external networks";
        after = [ "network-addresses-${netdev}.service" "firewall.service" ];
        requires = after;
        wantedBy = [ "network.target" ];
        bindsTo = [ "sys-subsystem-net-devices-${fclib.network.srv.physicalDevice}.device" ];
        path = [ pkgs.gawk pkgs.iproute pkgs.glibc pkgs.iptables ];

        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeScript "network-external-routing-start" ''
            #! ${pkgs.stdenv.shell} -ex
            echo "Adding routes via external network gateway ${gwHost}"
            echo "IPv4 gateway(s): ${gwIp4}"
            echo "IPv6 gateway(s): ${gwIp6}"
            for gw in ${gwIp4}; do
              # Onlink is required because the nexthop might be on a (redirected)
              # IP due to us sometimes having multiple networks on a segment.
              ip -4 route add ${extnet.vxlan4} via $gw dev ${netdev} onlink
            done
            for gw in ${gwIp6}; do
              # Note: The onlink hack above is not required for v6.
              ip -6 route add ${extnet.vxlan6} via $gw dev ${netdev}
            done
            iptables -I nixos-fw 3 -i ${netdev} -s ${extnet.vxlan4} \
              -j nixos-fw-accept
            ip6tables -I nixos-fw 3 -i ${netdev} -s ${extnet.vxlan6} \
              -j nixos-fw-accept
          '';
          ExecStop = pkgs.writeScript "network-external-routing-stop" ''
            #! ${pkgs.stdenv.shell}
            echo "Removing routes via external network gateway ${gwHost}"
            iptables -D nixos-fw -i ${netdev} -s ${extnet.vxlan4} \
              -j nixos-fw-accept
            ip6tables -D nixos-fw -i ${netdev} -s ${extnet.vxlan6} \
              -j nixos-fw-accept
            for gw in ${gwIp4}; do
              ip -4 route del ${extnet.vxlan4} via $gw dev ${netdev}
            done
            for gw in ${gwIp6}; do
              ip -6 route del ${extnet.vxlan6} via $gw dev ${netdev}
            done
          '';
          RemainAfterExit = true;
        };
      };
    }
  );
}
