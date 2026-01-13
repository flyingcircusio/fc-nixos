# Cluster IP range is 10.43.0.0/16 by default.
# The Kubernetes API server assigns virtual IPs for services from that subnet.
# This must not overlap with "real" subnets.
# It can be set with flyingcircus.kubernetes.network.serviceCidr.

{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.flyingcircus.kubernetes.network) enableIPv6;
in
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
        enableIPv6 = mkOption {
          type = types.bool;
          default = lib.versionAtLeast config.system.stateVersion "25.11";
          description = ''
            Enable IPv6 support for k3s clusters. When enabled, clusters will use
            dual-stack networking with both IPv4 and IPv6. This option is automatically
            enabled for clusters with state version >= 25.11, but can be overridden.
          '';
        };

        clusterDns = mkOption {
          type = types.listOf types.str;
          default =
            if enableIPv6 then
              [
                "fd00:43::a"
                "10.43.0.10"
              ]
            else
              [ "10.43.0.10" ];
          description = "Cluster IPs that should be used for CoreDNS.";
        };

        # These network specifications are supposed to hold at most one network
        # per IP family. Once platform-level IPv6 support for k3s arrives, it
        # makes sense to restructure this to single options of
        # kubernetes.network.ipv4 = { serviceCidr…; podCidr…;};
        # kubernetes.network.ipv6 = { serviceCidr…; podCidr…;};
        serviceCidr = mkOption {
          type = types.listOf types.str;
          default =
            if enableIPv6 then
              [
                "fd00:43::/112"
                "10.43.0.0/16"
              ]
            else
              [ "10.43.0.0/16" ];
          description = "IPs are assigned to services from the subnet specified here.";
        };

        podCidr = mkOption {
          type = types.listOf types.str;
          default =
            if enableIPv6 then
              [
                "fd00:42::/56"
                "10.42.0.0/16"
              ]
            else
              [ "10.42.0.0/16" ];
          description = "Kubernetes nodes get a /24 subnet for their pods from the given subnet.";
        };

        nodeIps = mkOption {
          type = with types; listOf str;
          internal = true;
          default = 
            let
              v6Addrs = config.fclib.network.srv.v6.addresses or [];
              v4Addrs = config.fclib.network.srv.v4.addresses or [];
            in
            lib.optional (enableIPv6 && v6Addrs != []) (head v6Addrs) ++
            lib.optional (v4Addrs != []) (head v4Addrs);
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
        assertions = [
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

        services.k3s.package = config.fclib.mkPlatform pkgs.k3s_1_32;

      }

      (lib.mkIf (server || agent) {
        flyingcircus.passwordlessSudoPackages = [
          {
            commands = [ "bin/fc-kubernetes" ];
            package = config.flyingcircus.agent.package;
            groups = [
              "admins"
              "sudo-srv"
            ];
          }
        ];
      })
    ];
}
