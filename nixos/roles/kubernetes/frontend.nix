# This role allows access to Kubernetes Service IPs (also called ClusterIPs, 10.0.0.0/24)
# and pod networks (10.1.0.0/16) on all nodes.
# HAProxy can be used to load-balance between pods with DNS service discovery.
#

{ config, lib, pkgs, ... }:

with builtins;
with config.flyingcircus.kubernetes.lib;

let
  fclib = config.fclib;
  cfg = config.flyingcircus.roles.kubernetes-frontend;
  master = fclib.findOneService "kubernetes-master-master";

  masterRoleEnabled = config.flyingcircus.roles.kubernetes-master.enable;
  nodeRoleEnabled = config.flyingcircus.roles.kubernetes-node.enable;
  location = lib.attrByPath [ "parameters" "location" ] "standalone" config.flyingcircus.enc;
  fcNameservers = config.flyingcircus.static.nameservers.${location} or [];


in
{
  options = with lib; {
    flyingcircus.roles.kubernetes-frontend = {
      enable = lib.mkEnableOption "Enable Kubernetes Frontend (experimental)";
      haproxyExtraConfig = mkOption {
        description = "Plain HAProxy config snippets appended to base config.";
        type = types.lines;
        default = "";
        example = ''
          listen ingress
              bind [2a02:238:f030:::1000]:80
              server-template svc 3 *.ingress.default.svc.cluster.local:80 check resolvers cluster init-addr none
          '';
      };
    };
  };

  config = lib.mkMerge [

    (lib.mkIf cfg.enable {

      assertions = [
        {
          assertion = master != null;
          message = "Invalid cluster configuration: No Kubernetes master found!";
        }
      ];

      flyingcircus.services.haproxy = {
        enable = true;
        enableStructuredConfig = true;
        defaults = {
          mode = "tcp";
          options = [
            "tcplog"
            "dontlognull"
          ];
        };
        listen = {
          "stats" = {
            mode = "http";
            binds = [ "127.0.0.1:8000" ];
            extraConfig = ''
              stats uri /
              stats refresh 5s
              stats admin if LOCALHOST
            '';
          };
        };
        extraConfig = ''
          resolvers cluster
            nameserver ${master.address} ${head master.ips}:53
            accepted_payload_size 8192 # allow larger DNS payloads

          # flyingcircus.roles.kubernetes-frontend.haproxyExtraConfig
          ${cfg.haproxyExtraConfig}
        '';
      };
    })

    (lib.mkIf (cfg.enable && !masterRoleEnabled && !nodeRoleEnabled) {

      # Policy routing interferes with virtual ClusterIPs handled by kube-proxy, disable it.
      flyingcircus.network.policyRouting.enable = false;

      # Needed for frontend-only machines.
      # The kubernetes-master role also sets the same token but in another directory.
      flyingcircus.activationScripts.kubernetes-apitoken-node = ''
        mkdir -p /var/lib/kubernetes/secrets
        umask 077
        echo ${master.password} | md5sum | head -c32 > /var/lib/kubernetes/secrets/apitoken.secret
      '';

      networking.nameservers = lib.mkOverride 90 (master.ips ++ fcNameservers);

      services.kubernetes = {
        easyCerts = true;
        flannel.enable = true;
        proxy.enable = true;
        # The certificates only support fcio.net but the directory still uses gocept.net
        # for historical reasons.
        masterAddress = lib.replaceStrings ["gocept.net"] ["fcio.net"] master.address;
        kubelet = {
          enable = true;
          taints = {
            frontend = {
              key = "node-role.kubernetes.io/frontend";
              value = "true";
              effect = "NoSchedule";
            };
          };
        };
      };

      systemd.services = lib.mapAttrs'
        mkUnitWaitForCerts
        {
          "flannel" = [ "flannel-client" ];
          "kube-proxy" = [ "kube-proxy-client" ];

          "kubelet" = [
            "kubelet"
            "kubelet-client"
          ];
        };
    })

  ];
}
