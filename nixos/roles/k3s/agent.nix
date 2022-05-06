{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.k3s-agent;
  fclib = config.fclib;
  server = fclib.findOneService "k3s-server-server";
  serverAddress = lib.replaceStrings ["gocept.net"] ["fcio.net"] server.address or "";
  agentAddress = head fclib.network.srv.v4.addresses;
  tokenFile = "/var/lib/k3s/secret_token";
  k3sFlags = [
    "--flannel-iface=${fclib.network.srv.device}"
    "--node-ip=${agentAddress}"
    "--data-dir=/var/lib/k3s"
  ];

in
{
  options = {
    flyingcircus.roles.k3s-agent = {
      enable = lib.mkEnableOption "Enable K3s (Kubernetes) Agent Node (experimental)";
      supportsContainers = fclib.mkDisableContainerSupport;
    };
  };

  config = lib.mkMerge [

    (lib.mkIf cfg.enable {

      assertions = [
        {
          assertion = server != null;
          message = "Invalid Cluster configuration: Kubernetes agent found but no server!";
        }
      ];

      boot.supportedFilesystems = [ "nfs" "nfs4" ];

      environment.systemPackages = with pkgs; [
        config.services.k3s.package
        bridge-utils
        nfs-utils
      ];

      flyingcircus.services.telegraf.inputs = {
        kubernetes  = [{
          # Works without auth on localhost.
          url = "http://localhost:10255";
          # If the string isn't defined, the kubernetes plugin uses a default location
          # for the bearer token which we don't use.
          bearer_token_string = "doesntmatter";
        }];
      };

      flyingcircus.activationScripts.kubernetes-apitoken-node = ''
        mkdir -p /var/lib/k3s
        umask 077
        echo ${server.password} | sha256sum | head -c64 > /var/lib/k3s/secret_token
      '';

      services.k3s = {
        enable = true;
        role = "agent";
        serverAddr = "https://${serverAddress}:6443";
        inherit tokenFile;
        extraFlags = lib.concatStringsSep " " k3sFlags;
      };

      users.users = {
        kubernetes = {
          isSystemUser = true;
          home = "/var/empty";
          extraGroups = [ "service" ];
          uid = config.ids.uids.kubernetes;
        };
      };

      ### Fixes for upstream issues

      # https://github.com/NixOS/nixpkgs/issues/103158
      systemd.services.k3s.after = [ "network-online.service" "firewall.service" ];
      systemd.services.k3s.serviceConfig.KillMode = lib.mkForce "control-group";

      # https://github.com/NixOS/nixpkgs/issues/98766
      boot.kernelModules = [ "ip_conntrack" "ip_vs" "ip_vs_rr" "ip_vs_wrr" "ip_vs_sh" ];
      networking.firewall.extraCommands = ''
        iptables -A INPUT -i cni+ -j ACCEPT
      '';
    })

  ];
}
