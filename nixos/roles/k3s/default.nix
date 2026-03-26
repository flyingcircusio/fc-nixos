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
  location = lib.attrByPath [ "parameters" "location" ] "standalone" config.flyingcircus.enc;
  lokiServer = config.fclib.findOneService "loki-collector";
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
          default = lib.versionAtLeast config.system.stateVersion "26.05";
          description = ''
            Enable IPv6 support for k3s clusters. When enabled, clusters will use
            dual-stack networking with both IPv4 and IPv6. This option is automatically
            enabled for clusters with state version >= 26.05, but can be overridden.
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
              v6Addrs = config.fclib.network.srv.v6.addresses or [ ];
              v4Addrs = config.fclib.network.srv.v4.addresses or [ ];
            in
            lib.optional (enableIPv6 && v6Addrs != [ ]) (head v6Addrs)
            ++ lib.optional (v4Addrs != [ ]) (head v4Addrs);
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

        services.k3s = {
          package = config.fclib.mkPlatform pkgs.k3s_1_32;
          extraKubeletConfig.imageGCLowThresholdPercent = config.fclib.mkPlatform 70;
          extraKubeletConfig.imageGCHighThresholdPercent = config.fclib.mkPlatform 75;
        };
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

      (lib.mkIf (server && (!builtins.isNull lokiServer)) {
        systemd.services.alloy = lib.mkIf config.services.alloy.enable {
          requires = [ "k3s.service" ];
          after = [ "k3s.service" ];

          serviceConfig.LoadCredential = "bearer_token_file:/var/lib/k3s/tokens/alloy";
          environment.BEARER_TOKEN_FILE = "%d/bearer_token_file";
          environment.API_SERVER = "https://127.0.0.1:6443";
          environment.CLUSTER_LOCATION = location;
          reloadTriggers = [
            config.environment.etc."alloy/k3s_events.alloy".source
            config.environment.etc."alloy/pod_logs.alloy".source
          ];
        };

        environment.etc."alloy/pod_logs.alloy".text = ''
          discovery.kubernetes "pods" {
            role = "pod"
            selectors {
              role = "pod"
            }
            api_server = sys.env("API_SERVER")
            bearer_token_file = sys.env("BEARER_TOKEN_FILE")
            tls_config {
              insecure_skip_verify = true
            }
          }

          discovery.relabel "pods" {
            targets = discovery.kubernetes.pods.targets

            rule {
              source_labels = ["__meta_kubernetes_pod_container_name"]
              action = "replace"
              target_label = "container"
            }

            rule {
              source_labels = ["__meta_kubernetes_pod_phase"]
              action = "replace"
              target_label = "phase"
            }
          }

          loki.source.kubernetes "pod_logs" {
            targets    = discovery.relabel.pods.output
            forward_to = [loki.process.pod_logs.receiver]
            client {
              api_server = sys.env("API_SERVER")
              bearer_token_file = sys.env("BEARER_TOKEN_FILE")
              tls_config {
                insecure_skip_verify = true
              }
            }
          }

          loki.process "pod_logs" {
            stage.static_labels {
                values = {
                  cluster = sys.env("CLUSTER_LOCATION"),
                }
            }

            forward_to = [loki.write.fcio_rg_loki.receiver]
          }
        '';

        environment.etc."alloy/k3s_events.alloy".text = ''
          loki.source.kubernetes_events "k3s_events" {
            forward_to = [loki.write.fcio_rg_loki.receiver]
            client {
              api_server = sys.env("API_SERVER")
              bearer_token_file = sys.env("BEARER_TOKEN_FILE")
              tls_config {
                insecure_skip_verify = true
              }
            }
          }
        '';
      })
    ];
}
