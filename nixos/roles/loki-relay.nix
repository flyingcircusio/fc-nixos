{ config, lib, ... }:
let
  cfg = config.flyingcircus.roles.loki-relay;
  fclib = config.fclib;
  enc = config.flyingcircus.enc;
  lokiPort = 3100;
in
{
  options = {
    flyingcircus.roles.loki-relay = {
      enable = lib.mkEnableOption "the Flying Circus Grafana Loki relay";
    };
  };

  config = lib.mkMerge [
    (
      # open ports for incoming logs from specific VMs in other RGs
      let
        roleConfig = enc.role_configuration."statshost-master";
        relayFrom = roleConfig.relay_from_details;
        makeRule =
          addr:
          "${fclib.iptables addr} -A nixos-fw -i ethsrv -s ${addr} -p tcp --dport ${builtins.toString lokiPort} -j nixos-fw-accept";

        makeHostBlock =
          name: value:
          lib.concatStringsSep "\n" ([ "# loki-relay from \"${name}\"" ] ++ (map makeRule value.addresses));
      in
      lib.mkIf (config.flyingcircus.roles.loki.enable && enc ? "role_configuration"."statshost-master") {
        networking.firewall.extraCommands = lib.concatStringsSep "\n\n" (
          lib.mapAttrsToList makeHostBlock relayFrom
        );
      }
    )
    (
      # open a relay for other VMs in this RG to route all logs to another RG (see above)
      # functionally this is identical to the single-RG loki-collector but instead of passing
      # the logs to a local loki instance this forwards the logs to another RG
      # this will eventually be replaced with a similar configuration for alloy that supports
      # sending logs out to multiple endpoints e.g. a global statshost
      let
        roleConfig = enc.role_configuration."statshost-relay";
        lokiHost = builtins.head roleConfig.relay_to;
      in
      lib.mkIf cfg.enable {
        flyingcircus.services.nginx = {
          enable = true;

          virtualHosts.loki = {
            serverName = config.networking.hostName;
            serverAliases = [
              (fclib.fqdn { vlan = "srv"; })
              "${config.networking.hostName}.${config.networking.domain}"
            ];
            listen = builtins.map (addr: {
              inherit addr;
              port = lokiPort;
            }) fclib.network.srv.dualstack.addressesQuoted;
            locations."/" = {
              proxyPass = "http://${lokiHost}:${toString lokiPort}";
              proxyWebsockets = true;
            };
          };
        };
      }
    )
  ];
}
