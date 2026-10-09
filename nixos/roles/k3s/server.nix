{
  config,
  lib,
  pkgs,
  ...
}:

with builtins;

let
  cfg = config.flyingcircus.roles.k3s-server;
  netCfg = config.flyingcircus.kubernetes.network;
  fclib = config.fclib;
  server = fclib.findOneService "k3s-server-server";

  location = lib.attrByPath [ "parameters" "location" ] "standalone" config.flyingcircus.enc;
  srvFQDN = "${config.networking.hostName}.fcio.net";
  lokiServer = fclib.findOneService "loki-collector";

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

  kubectlBin = lib.getExe pkgs.kubectl;
  jqBin = lib.getExe pkgs.jq;

  # Use the same location as NixOS k8s.
  defaultKubeconfig = "/etc/kubernetes/cluster-admin.kubeconfig";

  kubernetesMakeKubeconfig =
    let
      kc = kubectlBin;
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

  additionalManifests =
    let
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
          annotations."kubernetes.io/service-account.name" = "io.flyingcircus.service.${name}";
        };
      };
      authorizationApi =
        m:
        {
          apiVersion = "rbac.authorization.k8s.io/v1";
        }
        // m;
      clusterRole =
        c:
        {
          kind = "ClusterRole";
        }
        // (authorizationApi c);
      clusterRoleBinding =
        c:
        {
          kind = "ClusterRoleBinding";
        }
        // (authorizationApi c);

      manifests = [
        (serviceAccount "sensu-client")
        (serviceAccount "telegraf")
        (serviceAccountSecret "sensu-client")
        (serviceAccountSecret "telegraf")
        (clusterRole {
          metadata.name = "flyingcircus:sensu-client";
          rules = [
            {
              apiGroups = [ "" ];
              resources = [
                "nodes"
                "pods"
              ];
              verbs = [
                "get"
                "list"
              ];
            }
          ];
        })
        (clusterRoleBinding {
          metadata.name = "flyingcircus:sensu-client:viewer";
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = "flyingcircus:sensu-client";
          };
          subjects = [
            {
              kind = "ServiceAccount";
              name = "io.flyingcircus.service.sensu-client";
              namespace = "kube-system";
            }
          ];
        })
        (clusterRole {
          metadata = {
            name = "flyingcircus:cluster:viewer";
            labels."rbac.flyingcircus.io/aggregate-view-cluster" = "true";
          };
          rules = [
            {
              apiGroups = [ "" ];
              resources = [
                "persistentvolumes"
                "nodes"
              ];
              verbs = [
                "get"
                "list"
              ];
            }
            {
              apiGroups = [ "" ];
              resources = [ "secrets" ];
              verbs = [ "list" ];
            }
          ];
        })
        (clusterRole {
          metadata.name = "flyingcircus:telegraf";
          # aggregate the access control rules of the
          # flyingcircus:cluster:viewer role defined above and the
          # built-in view role
          aggregationRule.clusterRoleSelectors = map (m: { matchLabels."${m}" = "true"; }) [
            "rbac.flyingcircus.io/aggregate-view-cluster"
            "rbac.authorization.k8s.io/aggregate-to-view"
          ];
        })
        (clusterRoleBinding {
          metadata.name = "flyingcircus:telegraf:viewer";
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = "flyingcircus:telegraf";
          };
          subjects = [
            {
              kind = "ServiceAccount";
              name = "io.flyingcircus.service.telegraf";
              namespace = "kube-system";
            }
          ];
        })
        (clusterRole {
          metadata.name = "flyingcircus:daemonset:viewer";
          rules = [
            {
              apiGroups = [ "apps" ];
              resources = [ "daemonsets" ];
              verbs = [ "get" ];
            }
            {
              apiGroups = [ "" ];
              resources = [ "pods" ];
              verbs = [ "get" ];
            }
          ];
        })
        (clusterRoleBinding {
          metadata.name = "flyingcircus:nodes";
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = "flyingcircus:daemonset:viewer";
          };
          subjects = [
            {
              apiGroup = "rbac.authorization.k8s.io";
              kind = "Group";
              name = "system:nodes";
            }
          ];
        })
      ]
      ++ (lib.optionals (!builtins.isNull lokiServer) [
        (serviceAccount "alloy")
        (serviceAccountSecret "alloy")
        (clusterRole {
          metadata.name = "flyingcircus:alloy";
          rules = [
            {
              apiGroups = [ "" ];
              resources = [
                "pods"
                "pods/log"
              ];
              verbs = [
                "get"
                "list"
                "watch"
              ];
            }
          ];
        })
        (clusterRoleBinding {
          metadata.name = "flyingcircus:alloy:viewer";
          roleRef = {
            apiGroup = "rbac.authorization.k8s.io";
            kind = "ClusterRole";
            name = "flyingcircus:alloy";
          };
          subjects = [
            {
              kind = "ServiceAccount";
              name = "io.flyingcircus.service.alloy";
              namespace = "kube-system";
            }
          ];
        })
      ]);
      renderedManifests = lib.concatStringsSep "\n" (
        lib.flatten (
          map (m: [
            "---"
            (toJSON m)
          ]) manifests
        )
      );
    in
    pkgs.writeTextFile {
      name = "kubernetes-additional-manifests";
      text = renderedManifests;
      destination = "/flyingcircus.yaml";
    };

  authTokenScript = pkgs.writeShellScriptBin "kubernetes-write-auth-token" ''
    set -o pipefail

    tokenname="$1"
    secretname="$2"
    user="$3"
    group="$4"

    tokendir=/var/lib/k3s/tokens
    export KUBECONFIG=${defaultKubeconfig}

    mkdir -p "$tokendir"
    install -o "$user" -g "$group" -m 600 /dev/null "$tokendir/$tokenname.b64"
    install -o "$user" -g "$group" -m 600 /dev/null "$tokendir/$tokenname.tmp"
    install -o "$user" -g "$group" -m 600 /dev/null "$tokendir/$tokenname.cfg.tmp"

    # this service may race with k3s loading and processing the vendor
    # manifests from disk -- they are not present on first run, and k3s only
    # processes extra manifests after it has signalled readiness to
    # systemd. retry in case k3s has not initialised properly before
    # attempting to load this authentication token.

    rc=0
    for i in 1 2 3 4 5 6 7 8 9 10; do
      kubectl get -n kube-system -o jsonpath='{.data.token}' \
        secret "$secretname" > "$tokendir/$tokenname.b64" && \
        test -s "$tokendir/$tokenname.b64"
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

    base64 -d "$tokendir/$tokenname.b64" > "$tokendir/$tokenname.tmp"
    if [ "$?" != 0 ]; then
      echo 'could not decode secret token' 2>&1
      exit 1
    fi

    remarshal "$KUBECONFIG" -if yaml -of json | \
      jq --rawfile token "$tokendir/$tokenname.tmp" \
      '.users[0].user |= (del(."client-key-data", ."client-certificate-data") | .token = $token)' \
      > "$tokendir/$tokenname.cfg.tmp"
    if [ "$?" != 0 ]; then
      echo 'could not generate kubeconfig from token' 2>&1
      exit 1
    fi

    mv "$tokendir/$tokenname.tmp" "$tokendir/$tokenname"
    mv "$tokendir/$tokenname.cfg.tmp" "$tokendir/$tokenname.cfg"
    echo "Successfully initialised token with name \"$tokenname\" for secret \"$secretname\" for user \"$user\" in group \"$group\"."
    rm -f "$tokendir/$tokennname.b64"
  '';

  makeAuthTokenService =
    {
      user,
      secret,
      group ? user,
      tokenname ? user,
    }:
    {
      wantedBy = [ "multi-user.target" ];
      requires = [
        "k3s.service"
      ];
      after = [
        "k3s.service"
      ];
      path = with pkgs; [
        coreutils
        kubectl
        remarshal
        jq
      ];
      serviceConfig = {
        RemainAfterExit = true;
        Type = "oneshot";
        Restart = "on-failure";
        RestartSec = 10;
        ExecStart = "${authTokenScript}/bin/kubernetes-write-auth-token '${tokenname}' '${secret}' '${user}' '${group}'";
      };
    };

  podPendingScript = pkgs.writeScriptBin "check-kube-pending-pods" ''
    set -euo pipefail

    ret=0

    output=$(${kubectlBin} get \
      --kubeconfig /var/lib/k3s/tokens/sensuclient.cfg \
      pods -A -o json | \
      ${jqBin} -e '.items[] |
        select(.status.phase != "Running") |
        select(.status.phase != "Succeeded") |
        select(.status.conditions | map(.lastTransitionTime | fromdateiso8601 | ((now - .) > 600)) | any) |
        {
            "name": .metadata.name,
            "ns": .metadata.namespace,
            "phase": .status.phase,
            "since": .status.conditions[].lastTransitionTime,
            "message": .status.conditions[].message}
          | select(.message != null)' | ${jqBin} -s "unique") || ret=$?

    if [ "$ret" -eq "4" ]; then
        # no output, good.
        exit 0
    elif [ "$ret" -eq "0" ]; then
        # critical
        echo "$output"
        exit 2
    fi
  '';

in
{
  options = {
    flyingcircus.roles.k3s-server = {
      enable = lib.mkEnableOption "Enable K3s server (Kubernetes control plane, kube-dashboard) (only one per RG)";
      supportsContainers = fclib.mkDisableDevhostSupport;
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {

        environment.variables.KUBECONFIG = defaultKubeconfig;

        environment.systemPackages = with pkgs; [
          kubernetes-helm
          kubectl
          stern
          config.services.k3s.package
          kubernetesMakeKubeconfig
        ];

        flyingcircus.activationScripts.k3s-apitoken = lib.stringAfter [ "users" ] ''
          mkdir -p /var/lib/k3s
          umask 077
          token=/var/lib/k3s/secret_token
          echo ${server.password} | sha256sum | head -c64 > $token
          chmod 400 $token
        '';

        flyingcircus.services.postgresql = {
          enable = true;
          majorVersion = "14";
          autoUpgrade = {
            enable = true;
            expectedDatabases = [ "kubernetes" ];
          };
        };

        services.postgresql = {
          ensureDatabases = [ "kubernetes" ];
          ensureUsers = [
            {
              name = "root";
            }
          ];
        };

        systemd.services.fc-k3s-ensure-db-permissions = {
          description = "Ensure the root user has all permissions on kubernetes db";
          wantedBy = [ "k3s.service" ];
          before = [ "k3s.service" ];
          requires = [ "postgresql.service" ];
          script = ''
            PSQL="${config.services.postgresql.package}/bin/psql --port=${toString config.services.postgresql.settings.port}"
            for i in {1..10}; do
              $PSQL -d postgres -c "" 2> /dev/null && break
              sleep 0.5

              if [[ $i -eq 10 ]];then
                echo "couldn't establish connection to postgres"
                exit 1
            fi
            done
              $PSQL -tAc 'GRANT ALL PRIVILEGES ON DATABASE kubernetes TO "root"'
              $PSQL kubernetes -tAc 'GRANT CREATE ON SCHEMA public TO "root"'
          '';
          serviceConfig = {
            type = "oneshot";
          };
        };

        flyingcircus.services.sensu-client =
          let
            kc = "${pkgs.k3s}/bin/k3s kubectl";

            mkDnsCheck =
              idx: host:
              lib.nameValuePair "cluster-dns-${toString idx}" {
                notification = "Cluster DNS (CoreDNS) at ${host} is not healthy";
                command = ''
                  ${pkgs.monitoring-plugins}/bin/check_http -j HEAD -H '${host}' -p 9153 -u /metrics
                '';
              };
          in
          {
            checks = lib.listToAttrs (lib.imap0 mkDnsCheck netCfg.clusterDns) // {
              kube-events-warning = {
                notification = "Events of type 'Warning' occured in the Kubernetes cluster!";
                command = ''
                  export K3S_DATA_DIR=/var/tmp/sensu/k3s_data_dir
                  if test $(${kc} events --types=Warning --no-headers 2>/dev/null | wc -l) -ne 0; then
                    ${kc} events --types=Warning
                    exit 2
                  fi
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

              kube-pods-pending = {
                notification = "Pods have been in pending state for longer than 10 minutes";
                command = "${podPendingScript}/bin/check-kube-pending-pods";
              };
            };

            systemdUnitChecks = {
              "k3s.service" = { };
              "kube-dashboard.service" = { };
              "kube-dashboard-metrics-scraper.service" = { };
            };
          };

        flyingcircus.services.telegraf.inputs = {
          kube_inventory = [
            {
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
            }
          ];
        };

        services.k3s =
          let
            inherit (builtins) concatStringsSep;
            k3sFlags = [
              "--cluster-cidr='${concatStringsSep "," netCfg.podCidr}'"
              "--service-cidr='${concatStringsSep "," netCfg.serviceCidr}'"
              "--cluster-dns='${concatStringsSep "," netCfg.clusterDns}'"
              "--node-ip='${concatStringsSep "," netCfg.nodeIps}'"
              "--write-kubeconfig=${defaultKubeconfig}"
              "--node-taint=node-role.kubernetes.io/server=true:NoSchedule"
              "--flannel-backend=host-gw"
              "--flannel-iface=${fclib.network.srv.interface}"
              "--datastore-endpoint=postgres:///kubernetes?host=/run/postgresql"
              "--token-file=/var/lib/k3s/secret_token"
              "--data-dir=/var/lib/k3s"
              "--kube-apiserver-arg enable-admission-plugins=PodNodeSelector"
              # required for anonymous access to apiserver health port
              "--kube-apiserver-arg anonymous-auth=true"
            ]
            ++ (lib.optional netCfg.enableIPv6 "--flannel-ipv6-masq");
          in
          {
            enable = true;
            role = "server";
            extraFlags = k3sFlags;
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
            echo "Grant service access to k3s config file..."
            setfacl -m g:service:r ${defaultKubeconfig}
            echo "Grant kubernetes user access to k3s config file..."
            setfacl -m u:kubernetes:r ${defaultKubeconfig}
          '';
          serviceConfig = {
            RemainAfterExit = true;
            Type = "oneshot";
          };
        };

        # upstream provides the option services.k3s.manifests which
        # also uses tmpfiles rules for managing external manifests,
        # however we can't use this option as we use a different data
        # directory from the default.
        systemd.tmpfiles.rules = [
          "L+ /var/lib/k3s/server/manifests/flyingcircus/flyingcircus.yaml - - - - ${additionalManifests}/flyingcircus.yaml"
        ];

        systemd.services.fc-k3s-token-telegraf = makeAuthTokenService {
          user = "telegraf";
          secret = "io.flyingcircus.service-token.telegraf";
        };
        systemd.services.fc-k3s-token-sensuclient = makeAuthTokenService {
          user = "sensuclient";
          secret = "io.flyingcircus.service-token.sensu-client";
        };
        systemd.services.fc-k3s-token-alloy = lib.mkIf (!builtins.isNull lokiServer) (makeAuthTokenService {
          user = "root";
          tokenname = "alloy";
          secret = "io.flyingcircus.service-token.alloy";
        });
        systemd.services.telegraf.after = [ "fc-k3s-token-telegraf.service" ];
        systemd.services.sensu-client.after = [ "fc-k3s-token-sensuclient.service" ];
        systemd.services.alloy.after = lib.optionals (!builtins.isNull lokiServer) [
          "fc-k3s-token-alloy.service"
        ];

        ### Dashboard
        flyingcircus.services.nginx.enable = true;

        services.nginx.virtualHosts = {
          "${head fqdns}" = {
            enableACME = fclib.mkPlatform true;
            forceSSL = fclib.mkPlatform true;
            serverAliases = tail fqdns;
            # Listen on SRV + FE, as a SRV address is set as serverAlias
            listenAddresses =
              fclib.network.fe.dualstack.addressesQuoted ++ fclib.network.srv.dualstack.addressesQuoted;
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
          wants = [ "kube-dashboard-metrics-scraper.service" ];
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

        users.groups.kubernetes.gid = config.ids.gids.kubernetes;

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
        systemd.services.k3s.after = [
          "network-online.service"
          "firewall.service"
          "postgresql.service"
        ];
        systemd.services.k3s.requires = [
          "firewall.service"
          "postgresql.service"
        ];
        systemd.services.k3s.serviceConfig.KillMode = lib.mkForce "control-group";

        # https://github.com/NixOS/nixpkgs/issues/98766
        boot.kernelModules = [
          "ip_conntrack"
          "ip_vs"
          "ip_vs_rr"
          "ip_vs_wrr"
          "ip_vs_sh"
        ];
      }
    ]
  );
}
