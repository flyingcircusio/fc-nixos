{ config, lib, pkgs, ... }:

with builtins;
with config.flyingcircus.kubernetes.lib;

let
  cfg = config.flyingcircus.roles.kubernetes-node;
  fclib = config.fclib;
  kublib = config.services.kubernetes.lib;
  master = fclib.findOneService "kubernetes-master-master";
in
{
  options = {
    flyingcircus.roles.kubernetes-node = {
      enable = lib.mkEnableOption "Enable Kubernetes Node (experimental)";
    };
  };

  config = lib.mkMerge [

    (lib.mkIf cfg.enable {

      assertions = [
        {
          assertion = master != null;
          message = "Invalid Cluster configuration: Kubernetes node found but no master!";
        }
      ];

      environment.systemPackages = with pkgs; [
        bridge-utils
        nfs-utils
      ];

      services.kubernetes = {
        roles = [ "node" ];
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

      flyingcircus.services.telegraf.inputs = {
        kubernetes  = [{
          # Works without auth on localhost.
          url = "http://localhost:10255";
          # If the string isn't defined, the kubernetes plugin uses a default location
          # for the bearer token which we don't use.
          bearer_token_string = "doesntmatter";
        }];
      };
    })

    (lib.mkIf (cfg.enable && !config.flyingcircus.roles.kubernetes-master.enable) {

      # Policy routing interferes with virtual ClusterIPs handled by kube-proxy, disable it.
      flyingcircus.network.policyRouting.enable = false;

      # Needed for node-only machines.
      # The kubernetes-master role also sets the same token but in another directory.
      flyingcircus.activationScripts.kubernetes-apitoken-node = ''
        mkdir -p /var/lib/kubernetes/secrets
        umask 077
        echo ${master.password} | md5sum | head -c32 > /var/lib/kubernetes/secrets/apitoken.secret
      '';

      networking.nameservers = lib.mkOverride 90 master.ips;

      services.kubernetes = {
        # The certificates only support fcio.net but the directory still uses gocept.net
        # for historical reasons.
        masterAddress = lib.replaceStrings ["gocept.net"] ["fcio.net"] master.address;
      };

    })

  ];
}
