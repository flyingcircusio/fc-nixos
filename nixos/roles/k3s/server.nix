
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

  additionalManifests = let
    serviceAccount = name: {
      apiVersion = "v1";
      kind = "ServiceAccount";
      metadata = {
        name = "io.flyingcircus.service.${name}";
        namespace = "kube-system";
      };
    };
    serviceAccountSecret = name: {
      apiVersion = "v1";
      kind = "Secret";
      type = "kubernetes.io/service-account-token";
      metadata = {
        name = "io.flyingcircus.service-token.${name}";
        namespace = "kube-system";
        annotations."kubernetes.io/service-account.name" =
          "io.flyingcircus.service.${name}";
      };
    };
    authorizationApi = m: {
      apiVersion = "rbac.authorization.k8s.io/v1";
    } // m;
    clusterRole = c: {
      kind = "ClusterRole";
    } // (authorizationApi c);
    clusterRoleBinding = c: {
      kind = "ClusterRoleBinding";
    } // (authorizationApi c);

    manifests = [
      (serviceAccount "sensu-client")
      (serviceAccount "telegraf")
      (serviceAccountSecret "sensu-client")
      (serviceAccountSecret "telegraf")
      (clusterRole {
        metadata.name = "flyingcircus:sensu-client";
        rules = [{
          apiGroups = [""];
          resources = ["nodes"];
          verbs = ["get" "list"];
        }];
      })
      (clusterRoleBinding {
        metadata.name = "flyingcircus:sensu-client:viewer";
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "flyingcircus:sensu-client";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = "io.flyingcircus.service.sensu-client";
          namespace = "kube-system";
        }];
      })
      (clusterRole {
        metadata = {
          name = "flyingcircus:cluster:viewer";
          labels."rbac.flyingcircus.io/aggregate-view-cluster" = "true";
        };
        rules = [{
          apiGroups = [""];
          resources = ["persistentvolumes" "nodes"];
          verbs = ["get" "list"];
        }];
      })
      (clusterRole {
        metadata.name = "flyingcircus:telegraf";
        # aggregate the access control rules of the
        # flyingcircus:cluster:viewer role defined above and the
        # built-in view role
        aggregationRule.clusterRoleSelectors =
          map (m: { matchLabels."${m}" = "true"; }) [
            "rbac.flyingcircus.io/aggregate-view-cluster"
            "rbac.authorization.k8s.io/aggregate-to-view"
          ];
      })
      (clusterRoleBinding {
        metadata.name = "flyingcircus.telegraf:viewer";
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "flyingcircus:telegraf";
        };
        subjects = [{
          kind = "ServiceAccount";
          name = "io.flyingcircus.service.telegraf";
          namespace = "kube-system";
        }];
      })
    ];
    renderedManifests = lib.concatStringsSep "\n"
      (lib.flatten (map (m: ["---" (toJSON m)]) manifests));
  in pkgs.writeTextFile {
    name = "kubernetes-additional-manifests";
    text = renderedManifests;
    destination = "/flyingcircus.yaml";
  };

  authTokenScript = pkgs.writeShellScriptBin "kubernetes-write-auth-token" ''
    set -o pipefail

    user="$1"
    secret="$2"

    tokendir=/var/lib/k3s/tokens
    kubectl="${pkgs.kubectl}/bin/kubectl"
    export KUBECONFIG=${defaultKubeconfig}

    if [ -z "$secret" ]; then
      echo 'missing kubernetes secret name' 2>&1
      exit 1
    fi

    if [ -z "$user" ]; then
      echo 'missing service account name' 2>&1
      exit 1
    fi

    mkdir -p "$tokendir"
    install -o "$user" -g "$user" -m 600 /dev/null "$tokendir/$user.b64"
    install -o "$user" -g "$user" -m 600 /dev/null "$tokendir/$user.tmp"

    # this service may race with k3s loading and processing the vendor
    # manifests from disk -- they are not present on first run, and k3s only
    # processes extra manifests after it has signalled readiness to
    # systemd. retry in case k3s has not initialised properly before
    # attempting to load this authentication token.

    rc=0
    for i in 1 2 3 4 5; do
      "$kubectl" get -n kube-system -o jsonpath='{.data.token}' \
        secret "$secret" > "$tokendir/$user.b64" && \
        test -s "$tokendir/$user.b64"
      rc="$?"

      if [ "$rc" = 0 ]; then
         break
      fi
      sleep 1
    done

    if [ "$rc" != 0 ]; then
      echo 'could not read secret token' 2>&1
      exit 1
    fi

    base64 -d "$tokendir/$user.b64" > "$tokendir/$user.tmp"
    if [ "$?" != 0 ]; then
      echo 'could not decode secret token' 2>&1
      exit 1
    fi

    mv "$tokendir/$user.tmp" "$tokendir/$user"
    rm -f "$tokendir/$user.b64"
  '';

  makeAuthTokenService = user: secret: {
    wantedBy = [ "multi-user.target" ];
    requires = [ "k3s.service" "fc-k3s-load-manifests.service" ];
    after = [ "k3s.service" "fc-k3s-load-manifests.service" ];
    path = [ pkgs.coreutils ];
    serviceConfig = {
      RemainAfterExit = true;
      Type = "oneshot";
      Restart = "on-failure";
      RestartSec = 10;
      ExecStart = "${authTokenScript}/bin/kubernetes-write-auth-token ${user} ${secret}";
      ExecCondition = "${pkgs.coreutils}/bin/test ! -s /var/lib/k3s/tokens/${user}";
    };
  };

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

    flyingcircus.services.sensu-client = {
      checks = {
        cluster-dns = {
          notification = "Cluster DNS (CoreDNS) is not healthy";
          command = ''
            ${pkgs.monitoring-plugins}/bin/check_http -j HEAD -H ${netCfg.clusterDns} -p 9153 -u /metrics
          '';
        };

        kube-apiserver = {
          notification = "Kubernetes API server is not working";
          command = ''
            ${pkgs.monitoring-plugins}/bin/check_http -H localhost -p 6443 -S -u /healthz
          '';
        };

        kube-scheduler = {
          notification = "Kubernetes scheduler is not working";
          command = ''
            ${pkgs.monitoring-plugins}/bin/check_http -H localhost -p 10259 -S -u /healthz
          '';
        };

        kube-controller-manager = {
          notification = "Kubernetes controller manager is not working";
          command = ''
            ${pkgs.monitoring-plugins}/bin/check_http -H localhost -p 10257 -S -u /healthz
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

        kube-nodes-ready = {
          notification = "Kubernetes nodes are not in Ready state";
          command = ''
            ${pkgs.sensu-plugins-kubernetes}/bin/check-kube-nodes-ready.rb --token-file /var/lib/k3s/tokens/sensuclient -s https://localhost:6443
          '';
        };
      };

      systemdUnitChecks = {
        "k3s.service" = {};
        "kube-dashboard.service" = {};
        "kube-dashboard-metrics-scraper.service" = {};
      };
    };

    flyingcircus.services.telegraf.inputs = {
      kube_inventory = [{
        url = "https://localhost:6443";
        bearer_token = "/var/lib/k3s/tokens/telegraf";
        insecure_skip_verify = true;
        namespace = "";
        resource_exclude = [
          "persistentvolumes"
          "persistentvolumeclaims"
          "endpoints"
          "ingress"
        ];
      }];
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
        # required for anonymous access to apiserver health port
        "--kube-apiserver-arg anonymous-auth=true"
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

    systemd.services.fc-k3s-load-manifests = {
      wantedBy = [ "multi-user.target" ];
      requires = [ "k3s.service" ];
      after = [ "k3s.service" ];
      serviceConfig = {
        RemainAfterExit = true;
        Type = "oneshot";
      };
      path = [ pkgs.rsync ];
      restartTriggers = [ additionalManifests ];
      script = ''
        # copy additional vendor manifests into k3s's manifest
        # directory.
        set -x

        # this service may race with k3s creating its data
        # directory in the filesystem post-startup, so we give k3s
        # some grace time to complete this startup step.

        for i in 1 2 3 4 5; do
            if [ ! -d /var/lib/k3s/server/manifests ]; then
                sleep 0.5s
            else
                rsync --delete -rL ${additionalManifests}/ /var/lib/k3s/server/manifests/flyingcircus
                exit $?
            fi
        done

        exit 1
      '';
    };

    systemd.services.fc-k3s-token-telegraf =
      makeAuthTokenService "telegraf" "io.flyingcircus.service-token.telegraf";
    systemd.services.fc-k3s-token-sensuclient =
      makeAuthTokenService "sensuclient" "io.flyingcircus.service-token.sensu-client";
    systemd.services.telegraf.after = [ "fc-k3s-token-telegraf.service" ];
    systemd.services.sensu-client.after = [ "fc-k3s-token-sensuclient.service" ];

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
