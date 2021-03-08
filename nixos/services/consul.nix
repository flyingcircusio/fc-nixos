{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  cfg = config.flyingcircus.services.consul;
  enc = config.flyingcircus.enc;
  secrets = enc.parameters.secrets;
in
{
  options = {
    flyingcircus.services.consul = {
      enable = lib.mkEnableOption "Consul server";
    };
  };

  config = lib.mkIf cfg.enable {

    services.consul = {
      enable = true;
    };

    services.consul.extraConfig = let
      dc = config.flyingcircus.enc.parameters.resource_group;
      domain = "${config.flyingcircus.enc.parameters.location}.consul.local";
    in {
      primary_datacenter = dc;
      acl_default_policy = "deny";
      acl_down_policy = "extend-cache";
      client_addr = "{{ GetInterfaceIPs \"lo\" }}";
      datacenter = dc;
      dns_config = { node_ttl = "3s"; service_ttl = {"*" = "3s";};};
      domain =  domain;
      enable_script_checks = true;

      retry_join = map 
        (service: service.address)
        (fclib.findServices "consul_server-server");

      bind_addr = head (filter fclib.isIp6 (fclib.listenAddresses "ethsrv"));
      advertise_addr = head (filter fclib.isIp6 (fclib.listenAddresses "ethsrv"));

      acl.tokens.agent = secrets."consul/agent_token";
      encrypt = secrets."consul/encrypt";
    };


    flyingcircus.services.sensu-client.checks = {

      consul_proc = {
        notification = "Consul running";
        command = "${pkgs.monitoring-plugins}/bin/check_procs -C consul -w 1:11 -c 1:15";
      };

      consul_HTTP = {
        notification = "Consul HTTP";
        command = "${pkgs.monitoring-plugins}/bin/check_http -H localhost -p 8500 -u /v1/status/peers -w 1 -c 5";
      };

      consul_DNS = {
        notification = "Consul DNS";
        command = "${pkgs.monitoring-plugins}/bin/check_dns -c 5 -H ${enc.name}.node.${enc.parameters.resource_group}.${enc.parameters.location}.consul.local";
      };

    };

  };

}
