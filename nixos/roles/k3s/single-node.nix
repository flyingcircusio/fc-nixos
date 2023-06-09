# Simplified one-node setup for k3s.
# Useful as pipeline runner for Gitlab, for example.
# Limitations compared to our multi-node setup:
# * no dashboard
# * no frontend (services can only accessed from the same machine by default)
# * no postgres, only sqlite as state storage (cannot be moved to multi-server later)
# * no NFS storage class support

{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.k3s-single-node;
  netCfg = config.flyingcircus.kubernetes.network;
  fclib = config.fclib;

  location = lib.attrByPath [ "parameters" "location" ] "standalone" config.flyingcircus.enc;
  nodeAddress = head fclib.network.srv.v4.addresses;

  fcNameservers = config.flyingcircus.static.nameservers.${location} or [];

  # Use the same location as NixOS k8s.
  defaultKubeconfig = "/etc/kubernetes/cluster-admin.kubeconfig";

  kubernetesMakeKubeconfig = let
    kc = "${pkgs.kubectl}/bin/kubectl";
    remarshal = "${pkgs.remarshal}/bin/remarshal";
  in
  pkgs.writeScriptBin "kubernetes-make-kubeconfig" ''
    #!${pkgs.stdenv.shell} -e
    name=''${1:-$USER}
    src_config=/etc/kubernetes/cluster-admin.kubeconfig

    ${kc} get serviceaccount $name &> /dev/null \
      || ${kc} create serviceaccount $name > /dev/null

    ${kc} get clusterrolebinding cluster-admin-$name &> /dev/null \
      || ${kc} create clusterrolebinding cluster-admin-$name \
          --clusterrole=cluster-admin --serviceaccount=default:$name \
          > /dev/null

    ${kc} get secret $name-token &> /dev/null \
      || ${kc} apply -f - <<EOF > /dev/null
    apiVersion: v1
    kind: Secret
    type: kubernetes.io/service-account-token
    metadata:
      name: $name-token
      annotations:
        kubernetes.io/service-account.name: $name
    EOF

    token=$(${kc} describe secret $name-token | grep token: | cut -c 13-)

    ${remarshal} $src_config -if yaml -of json | \
      jq --arg token "$token" \
      '.users[0].user |= (del(."client-key-data", ."client-certificate-data") | .token = $token)' \
      > /tmp/$name.kubeconfig

    KUBECONFIG=/tmp/$name.kubeconfig ${kc} config view --flatten
    rm /tmp/$name.kubeconfig
  '';

in {
  options = {
    flyingcircus.roles.k3s-single-node = {
      enable = lib.mkEnableOption
        "Enable K3s everything on one node (Kubernetes control plane, kube-dashboard) (only one per RG)";
      supportsContainers = fclib.mkDisableContainerSupport;
    };
  };

  config = lib.mkIf cfg.enable {

    environment.variables.KUBECONFIG = defaultKubeconfig;

    environment.systemPackages = with pkgs; [
      kubernetes-helm
      kubectl
      stern
      config.services.k3s.package
      kubernetesMakeKubeconfig
      bridge-utils
    ];

    flyingcircus.services.sensu-client.checks = {

      cluster-dns = {
        notification = "Cluster DNS (CoreDNS) is not healthy";
        command = ''
          ${pkgs.monitoring-plugins}/bin/check_http -j HEAD -H ${netCfg.clusterDns} -p 9153 -u /metrics
        '';
      };

      k3s-kubelet = {
        notification = "K3s kubelet is not working";
        command = ''
          ${pkgs.monitoring-plugins}/bin/check_http -H localhost -p 10248 -u /healthz
        '';
      };

      k3s-proxy = {
        notification = "K3s proxy is not working";
        command = ''
          ${pkgs.monitoring-plugins}/bin/check_http -H localhost -p 10256 -u /healthz
        '';
      };

    };

    networking.firewall.extraCommands = ''
      iptables -I nixos-fw 1 -i cni+ -j ACCEPT
    '';


    networking.nameservers = lib.mkOverride 90 (lib.take 3 ([netCfg.clusterDns] ++ fcNameservers));

    services.k3s = let
      k3sFlags = [
        "--cluster-cidr=${netCfg.podCidr}"
        "--service-cidr=${netCfg.serviceCidr}"
        "--cluster-dns=${netCfg.clusterDns}"
        "--node-ip=${nodeAddress}"
        "--write-kubeconfig=${defaultKubeconfig}"
        "--flannel-backend=host-gw"
        "--flannel-iface=ethsrv"
        "--data-dir=/var/lib/k3s"
        "--kube-apiserver-arg enable-admission-plugins=PodNodeSelector"
        "--disable traefik"
      ];
    in {
      enable = true;
      extraFlags = lib.concatStringsSep " " k3sFlags;
    };

    systemd.services.fc-set-k3s-config-permissions = {
      requires = [ "k3s.service" ];
      partOf = [ "k3s.service" ];
      wantedBy = [ "k3s.service" ];
      after = [ "k3s.service" ];
      path = [ pkgs.acl ];
      script = ''
        echo "Grant sudo-srv access to k3s config file..."
        setfacl -m g:sudo-srv:r ${defaultKubeconfig}
        echo "Grant kubernetes user access to k3s config file..."
        setfacl -m u:kubernetes:r ${defaultKubeconfig}
      '';
      serviceConfig = {
        RemainAfterExit = true;
        Type = "oneshot";
      };
    };

    users.groups.kubernetes = {};

    users.users = {
      kubernetes = {
        isSystemUser = true;
        home = "/var/empty";
        extraGroups = [ "service" ];
        uid = config.ids.uids.kubernetes;
        group = "kubernetes";
      };
    };
  };
}
