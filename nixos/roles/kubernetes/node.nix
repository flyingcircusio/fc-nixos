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

      environment.systemPackages = with pkgs; [
        bridge-utils
      ];

      services.kubernetes = {
        # Kubelet doesn't start with swap by default but we want to use swap.
        kubelet.extraOpts = "--fail-swap-on=false";
        proxy = {
          # Works without proper hostname but avoids the error in kube-proxy log
          extraOpts = "--hostname-override=${config.networking.hostName}.fcio.net";
          # I don't really know what this bind address is for (has no visible effect)
          # but limiting it to srv is better than the default 0.0.0.0 default.
          bindAddress = head (fclib.listenAddresses "ethsrv");
        };
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
          url = "http://localhost:10255";
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

      services.kubernetes = {
        # The certificates only support fcio.net but the directory still uses gocept.net
        # for historical reasons.
        masterAddress = lib.replaceStrings ["gocept.net"] ["fcio.net"] master.address;
      };

    })

  ];
}
