# Cluster IP range is 10.42.0.0/16 by default.
# The Kubernetes API server assigns virtual IPs for services from that subnet.
# This must not overlap with "real" subnets.
# XXX: add option
# It can be set with services.kubernetes.apiserver.serviceClusterIpRange.

{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.k3s-server;
  fclib = config.fclib;
  server = fclib.findOneService "k3s-server-server";

  location = lib.attrByPath [ "parameters" "location" ] "standalone" config.flyingcircus.enc;
  srvFQDN = "${config.networking.hostName}.fcio.net";
  nodeAddress = head fclib.network.srv.v4.addresses;

  # We allow frontend access to the dashboard
  addresses = [
    "kubernetes.${fclib.currentRG}.fcio.net"
    (fclib.fqdn { vlan = "fe"; })
    srvFQDN
  ];

  fcNameservers = config.flyingcircus.static.nameservers.${location} or [];

  # Just the defaults here.
  defaultKubeconfig = "/etc/rancher/k3s/k3s.yaml";
  clusterCidr = "10.42.0.0/16";
  serviceCidr = "10.43.0.0/16";
  dnsClusterIp = "10.43.0.10";
  clusterDns = [ dnsClusterIp ];

  k3sFlags = [
    "--cluster-cidr=${clusterCidr}"
    "--service-cidr=${serviceCidr}"
    "--cluster-dns=${dnsClusterIp}"
    "--node-ip=${nodeAddress}"
    "--flannel-backend=host-gw"
    "--flannel-iface=ethsrv"
    "--no-deploy traefik"
    "--datastore-endpoint=postgres://kubernetes:kubernetes@localhost/k3s?sslmode=disable"
    "--token-file=/var/lib/k3s/secret_token"
    "--data-dir=/var/lib/k3s"
  ];

in
{
  options = {
    flyingcircus.roles.k3s-server = {
      enable = lib.mkEnableOption "Enable K3s (Kubernetes) (only one per RG; experimental)";
    };
  };

  config = lib.mkIf cfg.enable {

    environment.variables.KUBECONFIG = defaultKubeconfig;

    environment.shellAliases = {
      kubectl = "k3s kubectl";
    };

    environment.systemPackages = with pkgs; [
      kubernetes-helm
      stern
      config.services.k3s.package
    ];

    flyingcircus.activationScripts.k3s-apitoken =
      lib.stringAfter [ "users" ] ''
        mkdir -p /var/lib/k3s
        umask 077
        token=/var/lib/k3s/secret_token
        echo ${server.password} | sha256sum | head -c64 > $token
        chmod 400 $token
      '';

    flyingcircus.services.sensu-client.checks = let
    in
    {

      cluster-dns = {
        notification = "Cluster DNS (CoreDNS) is not healthy";
        command = ''
          ${pkgs.monitoring-plugins}/bin/check_http -j HEAD -H ${dnsClusterIp} -p 9153 -u /metrics
        '';
      };

      kube-apiserver = {
        notification = "Kubernetes API server is not working";
        command = ''
          ${pkgs.monitoring-plugins}/bin/check_http -j HEAD -H localhost -p 10251 -u /metrics
        '';
      };

      kube-dashboard-metrics-scraper = {
        notification = "Kubernetes dashboard metrics scraper sidecar is not working";
        command = ''
          ${pkgs.monitoring-plugins}/bin/check_http -H localhost -p 8000 -u /healthz
        '';
      };

      kube-dashboard = {
        notification = "Kubernetes dashboard backend is not working";
        command = ''
          ${pkgs.monitoring-plugins}/bin/check_http -H localhost -p 11000 -u /api/v1/namespace
        '';
      };

    };

    networking.nameservers = lib.mkOverride 90 (lib.take 3 (clusterDns ++ fcNameservers));

    services.k3s = {
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

    ### Dashboard
    flyingcircus.services.nginx.enable = true;

    services.nginx.virtualHosts = {
      "${head addresses}" = {
        enableACME = true;
        serverAliases = tail addresses;
        extraConfig = ''
          auth_basic "FCIO";
          auth_basic_user_file /etc/local/nginx/htpasswd_fcio_users;
        '';
        forceSSL = true;
        locations = {
          "/" = {
            root = "${pkgs.kubernetes-dashboard}/public/en";
          };

          "/api" = {
            proxyPass = "http://localhost:11000/api";
          };

          "/config" = {
            proxyPass = "http://localhost:11000/config";
          };
        };
      };
    };

    systemd.services.kube-dashboard = rec {
      requires = [ "k3s.service" ];
      wants = ["kube-dashboard-metrics-scraper.service" ];
      wantedBy = [ "multi-user.target" ];
      after = requires ++ wants;
      description = "Backend for Kubernetes Dashboard";
      script = ''
        ${pkgs.kubernetes-dashboard}/dashboard \
          --insecure-port 11000 \
          --kubeconfig ${defaultKubeconfig} \
          --sidecar-host http://localhost:8000
      '';

      serviceConfig = {
        Restart = "always";
        User = "kubernetes";
      };

    };

    systemd.services.kube-dashboard-metrics-scraper = rec {
      requires = [ "k3s.service" ];
      wantedBy = [ "multi-user.target" ];
      after = requires;
      description = "Metrics scraper sidecar for Kubernetes Dashboard";
      script = ''
        ${pkgs.kubernetes-dashboard-metrics-scraper}/metrics-sidecar \
          --kubeconfig ${defaultKubeconfig} \
          --db-file /var/lib/kube-dashboard/metrics.db
      '';

      serviceConfig = {
        Restart = "always";
        User = "kubernetes";
        StateDirectory = "kube-dashboard";
      };

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
    systemd.services.k3s.after = [ "network-online.service" "firewall.service" "postgresql.service" ];
    systemd.services.k3s.requires = [ "firewall.service" "postgresql.service"];
    systemd.services.k3s.serviceConfig.KillMode = lib.mkForce "control-group";

    # https://github.com/NixOS/nixpkgs/issues/98766
    boot.kernelModules = [ "ip_conntrack" "ip_vs" "ip_vs_rr" "ip_vs_wrr" "ip_vs_sh" ];
    networking.firewall.extraCommands = ''
      iptables -A INPUT -i cni+ -j ACCEPT
    '';
  };

}
