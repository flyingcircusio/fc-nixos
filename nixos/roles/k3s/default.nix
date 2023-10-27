# Cluster IP range is 10.43.0.0/16 by default.
# The Kubernetes API server assigns virtual IPs for services from that subnet.
# This must not overlap with "real" subnets.
# It can be set with flyingcircus.kubernetes.network.serviceCidr.

{ config, lib, pkgs, ... }:
{
  imports = with lib; [
    ./nfs.nix
    ./server.nix
    ./single-node.nix
    ./agent.nix
  ];

  options = with lib; {

    flyingcircus.kubernetes = {

      network = {

        clusterDns = mkOption {
          type = types.str;
          default = "10.43.0.10";
          description = "Cluster IP that should be used for CoreDNS.";
        };

        serviceCidr = mkOption {
          type = types.str;
          default = "10.43.0.0/16";
          description = "Cluster IPs are assigned to services from the subnet specified here.";
        };

        podCidr = mkOption {
          type = types.str;
          default = "10.42.0.0/16";
          description = "Kubernetes nodes get a /24 subnet for their pods from the given subnet.";
        };
      };
    };
  };

  config =
    let
      server = config.flyingcircus.roles.k3s-server.enable;
      agent = config.flyingcircus.roles.k3s-agent.enable;
      frontend = config.flyingcircus.roles.webgateway.enable;
    in
    lib.mkMerge [
    {
      assertions =
        [
          {
            assertion = !(server && agent);
            message = "The k3s-agent role must not be enabled together with the k3s-server role.";
          }
          {
            assertion = !(server && frontend);
            message = "The k3s-server role must not be enabled together with the webgateway (activates kubernetes frontend) role.";
          }
          {
            assertion = !(agent && frontend);
            message = "The k3s-agent role must not be enabled together with the webgateway (activates kubernetes frontend) role.";
          }
        ];

    }

    (lib.mkIf (server || agent) {
      flyingcircus.passwordlessSudoRules = [
        {
          commands = [
            "${config.flyingcircus.agent.package}/bin/fc-kubernetes"
            "/run/current-system/sw/bin/fc-kubernetes"
          ];
          groups = [ "admins" "sudo-srv" ];
        }
      ];
    })
  ];
}
