# All VMs in a RG with a Kubernetes cluster should be able to access
# Kubernetes Service IPs (also called ClusterIPs), including the cluster DNS
# service, dashboard and user-defined services.
# Sets a route for the (virtual) service network via the first Kubernetes node
# if one is present in the RG and this VM is not a node itself.
{ config, lib, pkgs, ... }:

with builtins;
with config.flyingcircus.kubernetes.lib;

let
  fclib = config.fclib;

  # XXX: This is the easiest choice, we could route via any Kubernetes node.
  nodeServices = fclib.findServices "kubernetes-node-node";
  isNode = config.flyingcircus.roles.kubernetes-node.enable;

  routerIP = if (nodeServices == [] || isNode)
    then null
    else head (head nodeServices).ips;

  master = fclib.findOneService "kubernetes-master-master";

  clusterNet = config.services.kubernetes.apiserver.serviceClusterIpRange;
  ipCmd = action: ''
    ip route ${action} ${clusterNet} via ${routerIP} dev ethsrv
  '';
in
{
  config = lib.mkIf (routerIP != null) {

    assertions = [
      {
        assertion = master != null;
        message = "Invalid cluster configuration: Kubernetes node found but no master!";
      }
    ];

    networking.nameservers = lib.mkOverride 90 master.ips;

    # Interferes with cluster networking, disable it.
    flyingcircus.network.policyRouting.enable = false;

    systemd.services.kubernetes-frontend-routing = rec {
      description = "IP routing from frontend VMs to the Kubernetes cluster network";
      after = [ "network-addresses-ethsrv.service" ];
      before = [ "network-local-commands.service" ];
      wantedBy = [ "multi-user.target" ];
      bindsTo = [ "sys-subsystem-net-devices-ethsrv.device" ] ++ after;
      path = [ fclib.relaxedIp ];
      script = ipCmd "add";
      preStop = ipCmd "del";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

  };

}
