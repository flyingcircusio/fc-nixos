{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  cfg = config.flyingcircus.services.consul;
  enc = config.flyingcircus.enc;
  secrets = enc.parameters.secrets;
  client_secret_script = fclib.python3BinFromFile ./update-client-secrets.py;
in
{
  options = {
    flyingcircus.services.consul = {
      enable = lib.mkEnableOption "Consul agent";

      watches = lib.mkOption {
          type = with lib.types; listOf attrs;
          description = ''
            List of Consul watches that get automatically extended
            with an appropriate token.
          '';
           default = [];
      };
    };
  };

  config = lib.mkIf cfg.enable {

    services.consul = {
      enable = true;
    };

    services.consul.extraConfig = let
      dc = enc.parameters.resource_group;
    in {
      primary_datacenter = dc;
      acl.default_policy = "deny";
      acl.down_policy = "extend-cache";

      client_addr = "{{ GetInterfaceIPs \"^lo$\" }}";
      datacenter = dc;
      dns_config = { node_ttl = "3s"; service_ttl = {"*" = "3s";};};
      enable_script_checks = true;

      retry_join = map
        (service: service.address)
        (fclib.findServices "consul_server-server");

      bind_addr = head fclib.network.srv.v6.addresses;
      advertise_addr = head fclib.network.srv.v6.addresses;
    };

    systemd.services.consul.restartTriggers = [
        (builtins.hashString "sha256" secrets."consul/master_token")
        (builtins.hashString "sha256" secrets."consul/agent_token")
        (secrets."consul/encrypt")
        client_secret_script
        config.environment.etc."consul.d/watches.json.in".text
      ];

    flyingcircus.activationScripts.consul-update-client-secrets = ''
      ${client_secret_script}/bin/update-client-secrets
    '';

    environment.etc."consul.d/watches.json.in".text = toJSON (
      { watches = cfg.watches; });

    flyingcircus.services.sensu-client.checks = {

      consul_proc = {
        notification = "Consul running";
        command = "${pkgs.monitoring-plugins}/bin/check_procs -C consul -w 1:11 -c 1:15";
      };

      consul_HTTP = {
        notification = "Consul HTTP";
        command = "${pkgs.monitoring-plugins}/bin/check_http -H localhost -p 8500 -u /v1/status/peers -w 1 -c 5";
      };

    };

  };

}
