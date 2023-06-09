
{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.k3s-server;
  netCfg = config.flyingcircus.kubernetes.network;
  fclib = config.fclib;
  server = fclib.findOneService "k3s-server-server";

  location = lib.attrByPath [ "parameters" "location" ] "standalone" config.flyingcircus.enc;
  srvFQDN = "${config.networking.hostName}.fcio.net";
  nodeAddress = head fclib.network.srv.v4.addresses;

  # We allow frontend access to the dashboard at the moment
  # via Nginx. The dashboard can be accessed by multiple names.
  # Unlike with the old kubernetes roles, the API is not public here.
  # If we choose to make it public, it should use the same fqdns
  # as the dashboard.
  fqdns = [
    # Alias set by directory automatically.
    "kubernetes.${fclib.currentRG}.fcio.net"
    # "Natural" frontend name.
    (fclib.fqdn { vlan = "fe"; })
    # Access via srv is also ok.
    srvFQDN
  ];

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
    flyingcircus.roles.k3s-server = {
      enable = lib.mkEnableOption
        "Enable K3s server (Kubernetes control plane, kube-dashboard) (only one per RG)";
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
    ];

    flyingcircus.activationScripts.k3s-apitoken =
      lib.stringAfter [ "users" ] ''
        mkdir -p /var/lib/k3s
        umask 077
        token=/var/lib/k3s/secret_token
        echo ${server.password} | sha256sum | head -c64 > $token
        chmod 400 $token
      '';

    flyingcircus.services.postgresql = {
      enable = true;
      majorVersion = "13";
    };

    services.postgresql = {
      ensureDatabases = [ "kubernetes" ];
      ensureUsers = [ {
        name = "root";
        ensurePermissions = {
          "DATABASE kubernetes" = "ALL PRIVILEGES";
        };
      } ];
    };

    flyingcircus.services.sensu-client.checks = {

      cluster-dns = {
        notification = "Cluster DNS (CoreDNS) is not healthy";
        command = ''
          ${pkgs.monitoring-plugins}/bin/check_http -j HEAD -H ${netCfg.clusterDns} -p 9153 -u /metrics
        '';
      };

      kube-apiserver = {
        notification = "Kubernetes API server is not working";
        command = ''
          ${pkgs.monitoring-plugins}/bin/check_http -j HEAD -H localhost -p 6443 --ssl -e HTTP/1.1
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
        # No access without kubeconfig, so 401 is expected here.
        command = ''
          ${pkgs.monitoring-plugins}/bin/check_http -H localhost -p 11000 -u /api/v1/namespace -e "HTTP/1.1 401"
        '';
      };
    };

    networking.nameservers = lib.mkOverride 90 (lib.take 3 ([netCfg.clusterDns] ++ fcNameservers));

    services.k3s = let
      k3sFlags = [
        "--cluster-cidr=${netCfg.podCidr}"
        "--service-cidr=${netCfg.serviceCidr}"
        "--cluster-dns=${netCfg.clusterDns}"
        "--node-ip=${nodeAddress}"
        "--write-kubeconfig=${defaultKubeconfig}"
        "--node-taint=node-role.kubernetes.io/server=true:NoSchedule"
        "--flannel-backend=host-gw"
        "--flannel-iface=ethsrv"
        "--datastore-endpoint=postgres://@:5432/kubernetes?host=/run/postgresql"
        "--token-file=/var/lib/k3s/secret_token"
        "--data-dir=/var/lib/k3s"
        "--kube-apiserver-arg enable-admission-plugins=PodNodeSelector"
      ];
    in {
      enable = true;
      role = "server";
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
      "${head fqdns}" = {
        enableACME = true;
        serverAliases = tail fqdns;
        forceSSL = true;
        locations = {
          "/" = {
            root = "${pkgs.kubernetes-dashboard}/public/en";
          };

          # This is the dashboard API, not the Kubernetes API!
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
          --authentication-mode token \
          --enable-insecure-login \
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

    ### Fixes for upstream issues

    # https://github.com/NixOS/nixpkgs/issues/103158
    systemd.services.k3s.after = [ "network-online.service" "firewall.service" "postgresql.service" ];
    systemd.services.k3s.requires = [ "firewall.service" "postgresql.service" ];
    systemd.services.k3s.serviceConfig.KillMode = lib.mkForce "control-group";

    # https://github.com/NixOS/nixpkgs/issues/98766
    boot.kernelModules = [ "ip_conntrack" "ip_vs" "ip_vs_rr" "ip_vs_wrr" "ip_vs_sh" ];
  };

}
