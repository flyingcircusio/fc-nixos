{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.kubernetes.addons.dashboard;
in {
  options.services.kubernetes.addons.dashboard = {
    enable = mkEnableOption "kubernetes dashboard addon";

    extraArgs = mkOption {
      description = "Extra arguments to append to the dashboard cmdline";
      type = types.listOf types.str;
      default = [];
      example = ["--enable-skip-login"];
    };

    rbac = mkOption {
      description = "Role-based access control (RBAC) options";
      default = {};
      type = types.submodule {
        options = {
          enable = mkOption {
            description = "Whether to enable role based access control is enabled for kubernetes dashboard";
            type = types.bool;
            default = elem "RBAC" config.services.kubernetes.apiserver.authorizationMode;
          };

          clusterAdmin = mkOption {
            description = "Whether to assign cluster admin rights to the kubernetes dashboard";
            type = types.bool;
            default = false;
          };
        };
      };
    };

    version = mkOption {
      description = "Which version of the kubernetes dashboard to deploy";
      type = types.str;
      default = "v2.0.3";
    };

    image = mkOption {
      description = "Docker image to seed for the kubernetes dashboard container.";
      type = types.attrs;
      default = {
        imageName = "kubernetesui/dashboard";
        imageDigest = "sha256:635b2efff46ac709b77ee699579e171aabc37a86a3e8c2c78153b763edcadcf4";
        finalImageTag = "v2.0.3";
        sha256 = "1xs64rqi05b2hkx2351v480fisd6hv4bx7bs1paidhvc9pnl8gh5";
      };
    };
  };

  config = mkIf cfg.enable {
    services.kubernetes.kubelet.seedDockerImages = [(pkgs.dockerTools.pullImage cfg.image)];

    services.kubernetes.addonManager.addons = {
      kubernetes-dashboard-deployment = {
        kind = "Deployment";
        apiVersion = "apps/v1";
        metadata = {
          labels = {
            k8s-addon = "kubernetes-dashboard.addons.k8s.io";
            k8s-app = "kubernetes-dashboard";
            version = cfg.version;
            "kubernetes.io/cluster-service" = "true";
            "addonmanager.kubernetes.io/mode" = "Reconcile";
          };
          name = "kubernetes-dashboard";
          namespace = "kube-system";
        };
        spec = {
          replicas = 1;
          revisionHistoryLimit = 10;
          selector.matchLabels."k8s-app" = "kubernetes-dashboard";
          template = {
            metadata = {
              labels = {
                k8s-addon = "kubernetes-dashboard.addons.k8s.io";
                k8s-app = "kubernetes-dashboard";
                version = cfg.version;
                "kubernetes.io/cluster-service" = "true";
              };
              annotations = {
                "scheduler.alpha.kubernetes.io/critical-pod" = "";
              };
            };
            spec = {
              priorityClassName = "system-cluster-critical";
              containers = [{
                name = "kubernetes-dashboard";
                image = with cfg.image; "${imageName}:${finalImageTag}";
                ports = [{
                  containerPort = 8443;
                  protocol = "TCP";
                }];
                resources = {
                  limits = {
                    cpu = "100m";
                    memory = "300Mi";
                  };
                  requests = {
                    cpu = "100m";
                    memory = "100Mi";
                  };
                };
                args = ["--auto-generate-certificates"] ++ cfg.extraArgs;
                volumeMounts = [{
                  name = "tmp-volume";
                  mountPath = "/tmp";
                } {
                  name = "kubernetes-dashboard-certs";
                  mountPath = "/certs";
                }];
                livenessProbe = {
                  httpGet = {
                    scheme = "HTTPS";
                    path = "/";
                    port = 8443;
                  };
                  initialDelaySeconds = 30;
                  timeoutSeconds = 30;
                };
              }];
              volumes = [{
                name = "kubernetes-dashboard-certs";
                secret = {
                  secretName = "kubernetes-dashboard-certs";
                };
              } {
                name = "tmp-volume";
                emptyDir = {};
              }];
              serviceAccountName = "kubernetes-dashboard";
              tolerations = [{
                key = "node-role.kubernetes.io/master";
                effect = "NoSchedule";
              } {
                key = "CriticalAddonsOnly";
                operator = "Exists";
              }];
            };
          };
        };
      };

      kubernetes-dashboard-svc = {
        apiVersion = "v1";
        kind = "Service";
        metadata = {
          labels = {
            k8s-addon = "kubernetes-dashboard.addons.k8s.io";
            k8s-app = "kubernetes-dashboard";
            "kubernetes.io/cluster-service" = "true";
            "kubernetes.io/name" = "KubeDashboard";
            "addonmanager.kubernetes.io/mode" = "Reconcile";
          };
          name = "kubernetes-dashboard";
          namespace  = "kube-system";
        };
        spec = {
          ports = [{
            port = 443;
            targetPort = 8443;
          }];
          selector.k8s-app = "kubernetes-dashboard";
        };
      };

      kubernetes-dashboard-sa = {
        apiVersion = "v1";
        kind = "ServiceAccount";
        metadata = {
          labels = {
            k8s-app = "kubernetes-dashboard";
            k8s-addon = "kubernetes-dashboard.addons.k8s.io";
            "addonmanager.kubernetes.io/mode" = "Reconcile";
          };
          name = "kubernetes-dashboard";
          namespace = "kube-system";
        };
      };
      kubernetes-dashboard-sec-csrf = {
        apiVersion = "v1";
        kind = "Secret";
        metadata = {
          labels = {
            k8s-app = "kubernetes-dashboard";
            # Allows editing resource and makes sure it is created first.
            "addonmanager.kubernetes.io/mode" = "EnsureExists";
          };
          name = "kubernetes-dashboard-csrf";
          namespace = "kube-system";
        };
        type = "Opaque";
      };
      kubernetes-dashboard-sec-certs = {
        apiVersion = "v1";
        kind = "Secret";
        metadata = {
          labels = {
            k8s-app = "kubernetes-dashboard";
            # Allows editing resource and makes sure it is created first.
            "addonmanager.kubernetes.io/mode" = "EnsureExists";
          };
          name = "kubernetes-dashboard-certs";
          namespace = "kube-system";
        };
        type = "Opaque";
      };
      kubernetes-dashboard-sec-kholder = {
        apiVersion = "v1";
        kind = "Secret";
        metadata = {
          labels = {
            k8s-app = "kubernetes-dashboard";
            # Allows editing resource and makes sure it is created first.
            "addonmanager.kubernetes.io/mode" = "EnsureExists";
          };
          name = "kubernetes-dashboard-key-holder";
          namespace = "kube-system";
        };
        type = "Opaque";
      };
      kubernetes-dashboard-cm = {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata = {
          labels = {
            k8s-app = "kubernetes-dashboard";
            # Allows editing resource and makes sure it is created first.
            "addonmanager.kubernetes.io/mode" = "EnsureExists";
          };
          name = "kubernetes-dashboard-settings";
          namespace = "kube-system";
        };
      };
    } // (optionalAttrs cfg.rbac.enable
      (let
        subjects = [{
          kind = "ServiceAccount";
          name = "kubernetes-dashboard";
          namespace = "kube-system";
        }];
        labels = {
          k8s-app = "kubernetes-dashboard";
          k8s-addon = "kubernetes-dashboard.addons.k8s.io";
          "addonmanager.kubernetes.io/mode" = "Reconcile";
        };
      in
        (if cfg.rbac.clusterAdmin then {
          kubernetes-dashboard-crb = {
            apiVersion = "rbac.authorization.k8s.io/v1";
            kind = "ClusterRoleBinding";
            metadata = {
              name = "kubernetes-dashboard";
              inherit labels;
            };
            roleRef = {
              apiGroup = "rbac.authorization.k8s.io";
              kind = "ClusterRole";
              name = "cluster-admin";
            };
            inherit subjects;
          };
        }
        else
        {
          # Upstream role- and rolebinding as per:
          # https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/alternative/kubernetes-dashboard.yaml
          kubernetes-dashboard-role = {
            apiVersion = "rbac.authorization.k8s.io/v1";
            kind = "Role";
            metadata = {
              name = "kubernetes-dashboard-minimal";
              namespace = "kube-system";
              inherit labels;
            };
            rules = [
              # Allow Dashboard to create 'kubernetes-dashboard-key-holder' secret.
              {
                apiGroups = [""];
                resources = ["secrets"];
                verbs = ["create"];
              }
              # Allow Dashboard to create 'kubernetes-dashboard-settings' config map.
              {
                apiGroups = [""];
                resources = ["configmaps"];
                verbs = ["create"];
              }
              # Allow Dashboard to get, update and delete Dashboard exclusive secrets.
              {
                apiGroups = [""];
                resources = ["secrets"];
                resourceNames = ["kubernetes-dashboard-key-holder" "kubernetes-dashboard-csrf"];
                verbs = ["get" "update" "delete"];
              }
              # Allow Dashboard to get and update 'kubernetes-dashboard-settings' config map.
              {
                apiGroups = [""];
                resources = ["configmaps"];
                resourceNames = ["kubernetes-dashboard-settings"];
                verbs = ["get" "update"];
              }
              # Allow Dashboard to get metrics from heapster.
              {
                apiGroups = [""];
                resources = ["services"];
                resourceNames = ["heapster"];
                verbs = ["proxy"];
              }
              {
                apiGroups = [""];
                resources = ["services/proxy"];
                resourceNames = ["heapster" "http:heapster:" "https:heapster:"];
                verbs = ["get"];
              }
            ];
          };

          kubernetes-dashboard-rb = {
            apiVersion = "rbac.authorization.k8s.io/v1";
            kind = "RoleBinding";
            metadata = {
              name = "kubernetes-dashboard-minimal";
              namespace = "kube-system";
              inherit labels;
            };
            roleRef = {
              apiGroup = "rbac.authorization.k8s.io";
              kind = "Role";
              name = "kubernetes-dashboard-minimal";
            };
            inherit subjects;
          };
        })
    ));
  };
}
