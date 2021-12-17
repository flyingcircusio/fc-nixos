# This services allows access to Kubernetes Service IPs (also called ClusterIPs, 10.43.0.0/16)
# and pod networks (10.42.0.0/16) on all nodes.
# HAProxy can be used to load-balance between pods with DNS service discovery.

{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  cfg = config.flyingcircus.services.k3s-frontend;
  netCfg = config.flyingcircus.kubernetes.network;
  frontendCfg = config.flyingcircus.kubernetes.frontend;
  server = fclib.findOneService "k3s-server-server";
  agents = fclib.findServices "k3s-agent-agent";
  serverAddress = lib.replaceStrings ["gocept.net"] ["fcio.net"] server.address or "";
  tokenFile = "/var/lib/k3s/secret_token";

  serverRoleEnabled = config.flyingcircus.roles.k3s-server.enable;
  agentRoleEnabled = config.flyingcircus.roles.k3s-agent.enable;
  location = lib.attrByPath [ "parameters" "location" ] "standalone" config.flyingcircus.enc;
  fcNameservers = config.flyingcircus.static.nameservers.${location} or [];

  serviceListenConfigs = lib.mapAttrs (name: conf:
    let
      serviceName = if (conf.serviceName != null) then conf.serviceName else name;
      serviceFqdn = "${serviceName}.${conf.namespace}.svc.cluster.local";
      binds =
        if (conf.binds != null) then conf.binds
        else
          let
            port = if conf.lbServicePort != null then conf.lbServicePort else conf.podPort;
          in [ "127.0.0.1:${toString port}" ];

      podOptions = lib.concatStringsSep " " [
        "check resolvers cluster init-addr none"
        (lib.optionalString conf.sslBackend "ssl verify none")
        (lib.optionalString (conf.extraPodTemplateOptions != "") conf.extraPodTemplateOptions)
      ];
      podDns = "*.${serviceFqdn}:${toString conf.podPort}";
      podInstances = toString conf.maxExpectedPods;
      podTemplate = "server-template pod ${podInstances} ${podDns} ${podOptions}";
    in
    assert
      lib.assertMsg (conf.lbServicePort != null || conf.podPort != null)
      "flyingcircus.kubernetes.frontend.${name}: podPort or lbServicePort must be set!";
    {
      inherit binds;
      inherit (conf) mode;
      servers =
        lib.optionals (conf.lbServicePort != null)
          (map
            (n: "${lib.replaceStrings [".gocept.net"] [""] n.address} ${head n.ips}:${toString conf.lbServicePort} check"
                + (lib.optionalString (conf.podPort != null) " backup")
                + (lib.optionalString conf.sslBackend " ssl verify none"))
            agents);

      extraConfig = lib.concatStringsSep "\n" [
        "balance leastconn"
        (lib.optionalString (conf.podPort != null) podTemplate)
        (lib.optionalString (conf.haproxyExtraConfig != "") "# From haproxyExtraConfig option")
        (lib.optionalString (conf.haproxyExtraConfig != "") conf.haproxyExtraConfig)
      ];
  }) frontendCfg;
in
{
  options = with lib; {

    flyingcircus.services.k3s-frontend.enable = mkEnableOption "Enable k3s (Kubernetes) Frontend";

    flyingcircus.kubernetes.frontend = mkOption {
      default = {};
      description = ''
        Configure the frontend haproxy to forward traffic to cluster services/pods.
      '';
      type = with types; attrsOf (submodule {

        options = {

          lbServicePort = mkOption {
            type = nullOr port;
            default = null;
            description = ''
              The port haproxy uses to talk to SRV addresses of the agents where
              the internal load balancer is listening, forwarding to the cluster IP of the service.
              This is called `port` in the Kubernetes service definition. The service
              must be of type `LoadBalancer`.

              Either `podPort` or `lbServicePort` must be defined.
              If only `lbServicePort` is specified, haproxy always talks to internal load balancer.
              If both are specified, talking to pods is preferred and the
              internal load balancer backends are configured as backups.

              Every agent is expected to run the internal load balancer
              so the number of backends is the same as the number of agents in the cluster.

              Talking to the internal load balancer works even without cluster
              DNS because we know the IPs of the agents from static config but
              is less performant than letting haproxy load balance between pods.
            '';
          };

          haproxyExtraConfig = mkOption {
            type = lines;
            default = "";
            description = "haproxy config lines added verbatim to the end of the listen block configured for this service.";
          };

          extraPodTemplateOptions = mkOption {
            type = string;
            default = "";
            description = "haproxy options for the server-template directive used for the pod backends, added verbatim to the end of the generated line.";
          };

          maxExpectedPods = mkOption {
            type = ints.positive;
            default = 10;
            description = "haproxy starts a fixed number of backends that are populated with pods found in the DNS response.
            If there are more pods than maxExpectedPods, some pods will be ignored by haproxy.";
          };

          mode = mkOption {
            type = enum [ "http" "tcp" ];
            default = "http";
            description = ''
              Run haproxy in TCP (layer 4) or HTTP mode (layer 7).
              Use TCP to forward HTTPS traffic if you have ingresses handling HTTPS themselves.
              It's recommended to terminate SSL on the Nginx in front of haproxy
              and let haproxy use HTTP mode to talk to the pods.
            '';
          };

          podPort = mkOption {
            type = nullOr port;
            default = null;
            description = ''
              The port haproxy uses to talk to the pods, load balancing between them.
              Haproxy uses DNS service discovery to update addresses of pods
              This is called `targetPort` in the Kubernetes service definition.
              which requires working Cluster DNS (it's enabled by default).
              Either `podPort` or `lbServicePort` must be defined.
              If only `podPort` is specified, haproxy only talks to the pods directly.
              If both are specified, talking to pods is preferred and the internal load balancer backends are configured as backups.
              If you leave `podPort` as null, haproxy talks to the internal load balancer only.
            '';
          };

          serviceName = mkOption {
            type = nullOr string;
            default = null;
            description = ''
              Name of the Kubernetes service we want to proxy.
              By default, the name of the Nix attribute is used as service name, so
              `flyingcircus.kubernetes.frontend.`.
              Changing the name here is required if a service publishes more than one port
              and you have to define two frontend configurations with
              different attribute names, for example.
              A typical case would be an ingress service which is handling both HTTP and HTTPS
              where you would have `frontend.kubernetes.frontend.ingress-http` and
              `ingress-https`, both pointing at the same serviceName `ingress`.
            '';
          };

          sslBackend = mkOption {
            type = bool;
            default = false;
            description = ''
              If the proxy should talk to the backend using SSL.
              Certificates are not verified to speed up things and make things work with self-signed certificates.
            '';
          };

          namespace = mkOption {
            type = string;
            default = "default";
            description = ''
              Kubernetes namespace the service is defined in.
              Uses the `default namespace by default.
            '';
          };

          binds = mkOption {
            type = nullOr (listOf str);
            default = null;
            example = map (a: "${a}:8080") fclib.network.fe.dualstack.addressesQuoted;
            description = ''Addresses with ports haproxy is binding to,
              listening for incoming connections. Defaults to 127.0.0.1, using either `lbServicePort`
              or `podPort`, if `lbServicePort` is not set.
            '';
          };

        };

      });
    };
  };

  config = lib.mkIf cfg.enable {

      flyingcircus.activationScripts.kubernetes-apitoken-node = ''
        mkdir -p /var/lib/k3s
        umask 077
        echo ${server.password} | sha256sum | head -c64 > /var/lib/k3s/secret_token
      '';

      flyingcircus.services.haproxy = {
        enable = true;
        enableStructuredConfig = true;
        defaults = {
          mode = "tcp";
          options = [
            "tcplog"
            "dontlognull"
          ];
        };
        listen = {
          "_stats" = {
            mode = "http";
            binds = [ "127.0.0.1:8000" ];
            extraConfig = ''
              stats uri /
              stats refresh 5s
              stats admin if LOCALHOST
            '';
          };
        } // serviceListenConfigs;
        extraConfig = ''
          resolvers cluster
            nameserver coredns ${netCfg.clusterDns}:53
            accepted_payload_size 8192 # allow larger DNS payloads
        '';
      };

      networking.nameservers = lib.mkOverride 90 (lib.take 3 ([netCfg.clusterDns] ++ fcNameservers));

      services.k3s = let
        nodeAddress = head fclib.network.srv.v4.addresses;
        k3sFlags = [
          "--flannel-iface=ethsrv"
          "--node-ip=${nodeAddress}"
          "--node-taint=node-role.kubernetes.io/server=true:NoSchedule"
          "--data-dir=/var/lib/k3s"
        ];

      in {
        enable = true;
        role = "agent";
        serverAddr = "https://${serverAddress}:6443";
        inherit tokenFile;
        extraFlags = lib.concatStringsSep " " k3sFlags;
      };

      ### Fixes for upstream issues

      # https://github.com/NixOS/nixpkgs/issues/103158
      systemd.services.k3s.after = [ "network-online.service" "firewall.service" ];
      systemd.services.k3s.serviceConfig.KillMode = lib.mkForce "control-group";

      # https://github.com/NixOS/nixpkgs/issues/98766
      boot.kernelModules = [ "ip_conntrack" "ip_vs" "ip_vs_rr" "ip_vs_wrr" "ip_vs_sh" ];
    };
}
