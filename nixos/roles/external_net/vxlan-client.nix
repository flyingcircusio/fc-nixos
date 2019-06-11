# Access external networks like VxLAN tunnels to Kamp DHP.
# The role activates itself if an appropriate ENC service is present and the host isn't a VxLAN gateway.

{ config, lib, pkgs, ... }:

let
  cfg = config.flyingcircus;
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
      extnet = cfg.roles.external_net;
    in
    {
      # does not interact well with old-style policy routing
      flyingcircus.network.policyRouting.enable = lib.mkForce false;

      systemd.services."network-external-routing" = rec {
        description = "Custom routing rules for external networks";
        after = [ "network-routing-ethsrv.service" "firewall.service" ];
        requires = after;
        wantedBy = [ "network.target" ];
        bindsTo = [ "sys-subsystem-net-devices-ethsrv.device" ];
        path = [ pkgs.gawk pkgs.iproute pkgs.glibc pkgs.iptables ];

        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeScript "network-external-routing-start" ''
            #! ${pkgs.stdenv.shell} -e
            echo "Adding routes via external network gateway ${gwHost}"
            gw4=$(getent ahostsv4 ${gwHost} | awk 'NR==1 {print $1}')
            gw6=$(getent ahostsv6 ${gwHost} | awk 'NR==1 {print $1}')
            ip -4 route add ${extnet.vxlan4} via $gw4 dev ethsrv
            ip -6 route add ${extnet.vxlan6} via $gw6 dev ethsrv
            iptables -I nixos-fw 3 -i ethsrv -s ${extnet.vxlan4} \
              -j nixos-fw-accept
            ip6tables -I nixos-fw 3 -i ethsrv -s ${extnet.vxlan6} \
              -j nixos-fw-accept
          '';
          ExecStop = pkgs.writeScript "network-external-routing-stop" ''
            #! ${pkgs.stdenv.shell}
            echo "Removing routes via external network gateway ${gwHost}"
            gw4=$(getent ahostsv4 ${gwHost} | awk 'NR==1 {print $1}')
            gw6=$(getent ahostsv6 ${gwHost} | awk 'NR==1 {print $1}')
            ip -4 route del ${extnet.vxlan4} via $gw4 dev ethsrv
            ip -6 route del ${extnet.vxlan6} via $gw6 dev ethsrv
            iptables -D nixos-fw -i ethsrv -s ${extnet.vxlan4} \
              -j nixos-fw-accept
            ip6tables -D nixos-fw -i ethsrv -s ${extnet.vxlan6} \
              -j nixos-fw-accept
          '';
          RemainAfterExit = true;
        };
      };
    }
  );
}
