# Cluster IP range is 10.43.0.0/16 by default.
# The Kubernetes API server assigns virtual IPs for services from that subnet.
# This must not overlap with "real" subnets.
# It can be set with flyingcircus.kubernetes.network.serviceCidr.

{ config, lib, pkgs, ... }:
{
  imports = with lib; [
    ./nfs.nix
    ./server.nix
    ./agent.nix
    (mkRenamedOptionModule
      [ "flyingcircus" "roles" "kubernetes-master" ]
      [ "flyingcircus" "roles" "k3s-server" ])
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

  config = {

    assertions =
      let server = config.flyingcircus.roles.k3s-server.enable;
          agent = config.flyingcircus.roles.k3s-agent.enable;
          frontend = config.flyingcircus.roles.webgateway.enable;
      in
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
  };

}
