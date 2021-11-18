# This services allows access to Kubernetes Service IPs (also called ClusterIPs, 10.0.0.0/24)
# and pod networks (10.1.0.0/16) on all nodes.
# HAProxy can be used to load-balance between pods with DNS service discovery.
#

{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  cfg = config.flyingcircus.services.k3s-frontend;
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
    in
    assert
      lib.assertMsg (conf.internalPort != null || conf.podPort != null)
      "flyingcircus.kubernetes.frontend.${name}: podPort or internalPort must be set!";
    {
      mode = conf.mode;
      binds = map (a: "${a}:${toString conf.lbPort}") conf.publicAddresses;
      servers =
        lib.optionals (conf.internalPort != null)
          (map
            (n: "${lib.replaceStrings [".gocept.net"] [""] n.address} ${head n.ips}:${toString conf.internalPort} check"
                + (lib.optionalString (conf.podPort != null) " backup"))
            agents);

      extraConfig = ''
        balance leastconn
      '' + lib.optionalString (conf.podPort != null) ''
        server-template pod ${toString conf.maxExpectedPods} *.${serviceName}.${conf.namespace}.svc.cluster.local:${toString conf.podPort} check resolvers cluster init-addr none
      '' + lib.optionalString (conf.haproxyExtraConfig != "") ''
        # frontend haproxyExtraConfig
        ${conf.haproxyExtraConfig}
      '';
  }) frontendCfg;
in
{
  options = with lib; {

    flyingcircus.services.k3s-frontend.enable = mkEnableOption "Enable Kubernetes Frontend";

    flyingcircus.kubernetes.frontend = mkOption {
      default = {};
      type = with types; attrsOf (submodule {

        options = {

          lbPort = mkOption {
            type = port;
          };

          internalPort = mkOption {
            type = nullOr port;
            default = null;
          };

          haproxyExtraConfig = mkOption {
            type = lines;
            default = "";
          };

          maxExpectedPods = mkOption {
            type = ints.positive;
            default = 10;
          };

          mode = mkOption {
            type = enum [ "http" "tcp" ];
            default = "http";
          };

          podPort = mkOption {
            type = nullOr port;
            default = null;
          };

          serviceName = mkOption {
            type = nullOr string;
            default = null;
          };

          namespace = mkOption {
            type = string;
            default = "default";
          };

          publicAddresses = mkOption {
            type = lib.types.listOf lib.types.str;
            default = fclib.network.fe.dualstack.addressesQuoted;
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
            nameserver coredns 10.43.0.10:53
            accepted_payload_size 8192 # allow larger DNS payloads
        '';
      };

      networking.nameservers = lib.mkOverride 90 (server.ips ++ fcNameservers);

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
