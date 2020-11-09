# Cluster IP range is 10.0.0.0/24 by default.
# The Kubernetes API server assigns virtual IPs for services from that subnet.
# This must not overlap with "real" subnets.
# It can be set with services.kubernetes.apiserver.serviceClusterIpRange.

{ config, lib, pkgs, ... }:

with builtins;
with config.flyingcircus.kubernetes.lib;

let
  cfg = config.flyingcircus.roles.kubernetes-master;
  fclib = config.fclib;
  kublib = config.services.kubernetes.lib;
  master = fclib.findOneService "kubernetes-master-master";

  domain = config.networking.domain;
  location = lib.attrByPath [ "parameters" "location" ] "standalone" config.flyingcircus.enc;
  feFQDN = "${config.networking.hostName}.fe.${location}.${domain}";
  srvFQDN = "${config.networking.hostName}.fcio.net";


  # Nginx uses default HTTP(S) ports, API server must use an alternative port.
  apiserverPort = 6443;

  # We allow frontend access to the dashboard and the apiserver for external
  # dashboards and kubectl. Names can be used for both dashboard and API server.
  addresses = [
    "kubernetes.${fclib.currentRG}.fcio.net"
    feFQDN
    srvFQDN
  ];

  # We don't care how the API is accessed but we have to choose one here for
  # the auto-generated configs.
  apiserverMainUrl = "https://${head addresses}:${toString apiserverPort}";

  fcNameservers = config.flyingcircus.static.nameservers.${location} or [];

  secret = name: "${config.services.kubernetes.secretsPath}/${name}.pem";

  mkAdminCert = username: rec {
    action = "";
    hosts = [];
    profile = "user";
    name = username;

    caCert = secret "ca";
    cert = secret username;
    CN = username;
    fields = {
      O = "system:masters";
    };
    key = secret "${username}-key";
    privateKeyOptions = {
      owner = username;
      group = "nogroup";
      mode = "0600";
      path = key;
    };
  };

  mkUserKubeConfig = cert:
   kublib.mkKubeConfig cert.name {
    certFile = cert.cert;
    keyFile = cert.key;
    server = apiserverMainUrl;
   };

  kubernetesMakeKubeconfig = pkgs.writeScriptBin "kubernetes-make-kubeconfig" ''
    #!${pkgs.stdenv.shell} -e
    name=''${1:-$USER}

    kubectl get serviceaccount $name &> /dev/null \
      || kubectl create serviceaccount $name > /dev/null

    kubectl get clusterrolebinding cluster-admin-$name &> /dev/null \
      || kubectl create clusterrolebinding cluster-admin-$name \
          --clusterrole=cluster-admin --serviceaccount=default:$name \
          > /dev/null

    token=$(kubectl describe secret $name-token | grep token: | cut -c 13-)

    jq --arg token "$token" '.users[0].user.token = $token' \
      < /etc/kubernetes/$name.kubeconfig > /tmp/$name.kubeconfig

    KUBECONFIG=/tmp/$name.kubeconfig kubectl config view --flatten
    rm /tmp/$name.kubeconfig
  '';

  kubernetesEtcdctl = pkgs.writeScriptBin "kubernetes-etcdctl" ''
    #!${pkgs.stdenv.shell}
    ETCDCTL_API=3 etcdctl --endpoints "https://etcd.local:2379" \
      --cacert /var/lib/kubernetes/secrets/ca.pem \
      --cert /var/lib/kubernetes/secrets/etcd.pem \
      --key /var/lib/kubernetes/secrets/etcd-key.pem \
      "$@"
  '';

  # sudo-srv users get their own cert with cluster-admin permissions.
  adminCerts =
    lib.listToAttrs
      (map
        (user: lib.nameValuePair user (mkAdminCert user))
        (fclib.usersInGroup "sudo-srv")
      );

  allCerts = adminCerts // {
    coredns = kublib.mkCert {
      name = "coredns";
      CN = "coredns";
      fields = {
        O = "default:coredns";
      };
      action = "systemctl restart coredns.service";
    };

    kube-dashboard = kublib.mkCert {
      name = "kube-dashboard";
      CN = "kube-dashboard";
      fields = {
        O = "system:masters";
      };
      action = "systemctl restart kube-dashboard.service";
    };

    sensu = kublib.mkCert {
      name = "sensu";
      CN = "sensu";
      fields = {
        O = "default:sensu";
      };
      privateKeyOwner = "sensuclient";
    };
  };

  # Grant view permission for sensu check (identified by sensuCert).
  sensuClusterRoleBinding = pkgs.writeText "sensu-crb.json" (toJSON {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "ClusterRoleBinding";
    metadata = {
      name = "sensu";
    };
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io";
      kind = "ClusterRole";
      name = "view";
    };
    subjects = [{
      kind = "User";
      name = "sensu";
    }];
  });

  # Grant view permission for coredns (identified by coredns cert).
  corednsClusterRoleBinding = pkgs.writeText "coredns-crb.json" (toJSON {
    apiVersion = "rbac.authorization.k8s.io/v1";
    kind = "ClusterRoleBinding";
    metadata = {
      name = "coredns";
    };
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io";
      kind = "ClusterRole";
      name = "view";
    };
    subjects = [{
      kind = "User";
      name = "coredns";
    }];
  });

  systemdServices = {

      coredns = rec {
        requires = [ "kube-apiserver.service" ];
        after = requires;
        serviceConfig = {
          Restart = lib.mkForce "always";
          ExecStartPre = ''
            +${pkgs.coreutils}/bin/chown coredns \
              /var/lib/kubernetes/secrets/coredns.pem \
              /var/lib/kubernetes/secrets/coredns-key.pem
          '';
        };
      };

      kube-dashboard = rec {
        requires = [ "kube-apiserver.service" ];
        after = requires;
        description = "Backend for Kubernetes Dashboard";
        script = ''
          ${pkgs.kubernetes-dashboard}/dashboard \
            --insecure-port 11000 \
            --kubeconfig /etc/kubernetes/kube-dashboard.kubeconfig
        '';

        serviceConfig = {
          Restart = "always";
          ExecStartPre = ''
            +${pkgs.coreutils}/bin/chown kube-dashboard \
              /var/lib/kubernetes/secrets/kube-dashboard.pem \
              /var/lib/kubernetes/secrets/kube-dashboard-key.pem
          '';
          DynamicUser = true;
        };

      };

      kube-apiserver = {
        serviceConfig = {
          Environment = [
            "GODEBUG=x509ignoreCN=0"
          ];
        };
      };

      fc-kubernetes-setup = rec {
        description = "Setup permissions for monitoring and dns";
        requires = [ "kube-apiserver.service" ];
        after = requires;
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.kubectl ];
        script = ''
          kubectl apply -f ${sensuClusterRoleBinding}
          kubectl apply -f ${corednsClusterRoleBinding}
        '';
        serviceConfig = {
          Environment = "KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig";
          Type = "oneshot";
          RemainAfterExit = true;
        };
      };
    };

   waitForCerts =
    lib.mapAttrs'
        mkUnitWaitForCerts
        {
          "etcd" = [ "etcd" ];
          "fc-kubernetes-setup" = [ "coredns" "sensu" ];
          "flannel" = [ "flannel-client" ];

          "kube-apiserver" = [
            "kube-apiserver"
            "kube-apiserver-kubelet-client"
            "kube-apiserver-etcd-client"
            "service-account"
          ];

          "kube-proxy" = [ "kube-proxy-client" ];

          "kube-controller-manager" = [
            "kube-controller-manager"
            "kube-controller-manager-client"
            "service-account"
          ];
        };

in
{
  options = {
    flyingcircus.roles.kubernetes-master = {
      enable = lib.mkEnableOption "Enable Kubernetes Master (only one per RG; experimental)";
    };
  };

  config = lib.mkIf cfg.enable {

    # Create kubeconfigs for all users with an admin cert (sudo-srv).
    environment.etc =
      lib.mapAttrs'
        (n: v: lib.nameValuePair
          "/kubernetes/${n}.kubeconfig"
          { source = mkUserKubeConfig v; })
        allCerts;

    environment.shellInit = lib.mkAfter ''
      # Root uses the cluster-admin cert generated by NixOS.
      if [[ $UID == 0 ]]; then
        export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig
      else
        export KUBECONFIG=/etc/kubernetes/$USER.kubeconfig
      fi
    '';

    environment.systemPackages = with pkgs; [
      kubectl
      kubernetes-helm
      kubernetesEtcdctl
      kubernetesMakeKubeconfig
      sensu-plugins-kubernetes
    ];

    # Policy routing interferes with virtual ClusterIPs handled by kube-proxy, disable it.
    flyingcircus.network.policyRouting.enable = false;

    flyingcircus.activationScripts.kubernetes-apitoken =
      lib.stringAfter [ "users" ] ''
        mkdir -p /var/lib/cfssl
        umask 077
        token=/var/lib/cfssl/apitoken.secret
        echo ${master.password} | md5sum | head -c32 > $token
        chown cfssl $token && chmod 400 $token
      '';

    flyingcircus.services.sensu-client.checks = let
      bin = "${pkgs.sensu-plugins-kubernetes}/bin";
      cfg = "--kube-config /etc/kubernetes/sensu.kubeconfig";
    in
    {

      cluster-dns = {
        notification = "Cluster DNS (CoreDNS) is not healthy";
        command = ''
          ${pkgs.monitoring-plugins}/bin/check_http -v -j HEAD -H localhost -p 10054 -u /health
        '';
      };

      kube-apiserver = {
        notification = "Kubernetes API server is not working";
        command = ''
          ${bin}/check-kube-apiserver-available.rb ${cfg}
        '';
      };

      kube-dashboard = {
        notification = "Kubernetes dashboard backend is not working";
        command = ''
          ${pkgs.monitoring-plugins}/bin/check_http -H localhost -p 11000 -u /api/v1/namespace
        '';
      };

    };

    networking.nameservers = [ "127.0.0.1" ];

    networking.firewall = {
      allowedTCPPorts = [ apiserverPort ];
    };

    services.coredns = {
      enable = true;
      config = ''
      . {
        kubernetes cluster.local {
          endpoint https://${srvFQDN}:${toString apiserverPort}
          tls /var/lib/kubernetes/secrets/coredns.pem /var/lib/kubernetes/secrets/coredns-key.pem /var/lib/kubernetes/secrets/ca.pem
          pods verified
        }

        ${lib.optionalString (fcNameservers != []) ''forward . ${lib.concatStringsSep " " fcNameservers}''}

        cache 30
        errors
        health :10054
        loadbalance
        log
        loop
        metadata
        prometheus :10055
        reload
      }
      '';
    };

    services.kubernetes = {
      addons.dns.enable = lib.mkForce false;
      apiserver.extraSANs = addresses;
      # Changing the masterAddress is tricky and requires manual intervention.
      # This would break automatic certificate management with certmgr.
      # SRV seems like the safest choice here.
      masterAddress = srvFQDN;
      # We already do that in the activation script.
      pki.genCfsslAPIToken = false;
      roles = [ "master" ];
    };

    # Serves public Kubernetes dashboard.
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

    services.kubernetes.pki.certs = allCerts;

    systemd.services = lib.recursiveUpdate systemdServices waitForCerts;

  };

}
