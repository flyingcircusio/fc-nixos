{ config, lib, ... }:

let
  cfg = config.flyingcircus;

  fclib = config.fclib;

  enc = fclib.jsonFromFile cfg.encPath {};

  encAddresses.srv = fclib.jsonFromFile cfg.encAddressesPath.srv "[]";

  encServices = fclib.jsonFromFile cfg.encServicesPath "[]";

  encServiceClients = fclib.jsonFromFile cfg.encServiceClientsPath "[]";

  systemState = fclib.jsonFromFile cfg.systemStatePath "{}";

in
{
  options.flyingcircus = with lib.types;
  {

    enc = lib.mkOption {
      type = attrs;
      description = "Data from the external node classifier.";
    };

    encPath = lib.mkOption {
      default = "/etc/nixos/enc.json";
      type = path;
      description = "Where to find the ENC json file.";
    };

    encAddresses.srv = lib.mkOption {
      type = listOf attrs;
      description = "List of addresses of machines in the neighbourhood.";
      example = [ {
        ip = "2a02:238:f030:1c3::104c/64";
        mac = "02:00:00:03:11:b1";
        name = "test03";
        rg = "test";
        rg_parent = "";
        ring = 1;
        vlan = "srv";
      } ];
    };

    encAddressesPath.srv = lib.mkOption {
      default = /etc/nixos/addresses_srv.json;
      type = path;
      description = "Where to find the address list json file.";
    };

    systemState = lib.mkOption {
      type = attrs;
      description = "The current system state as put out by fc-manage";
    };

    encServicesPath = lib.mkOption {
      default = /etc/nixos/services.json;
      type = path;
      description = "Where to find the ENC services json file.";
    };

    encServiceClients = lib.mkOption {
      type = listOf attrs;
      description = ''
        Service clients in the environment as provided by the ENC.
      '';
    };

    encServiceClientsPath = lib.mkOption {
      default = /etc/nixos/service_clients.json;
      type = path;
      description = "Where to find the ENC service clients json file.";
    };

    systemStatePath = lib.mkOption {
      default = /etc/nixos/system_state.json;
      type = path;
      description = "Where to find the system state json file.";
    };

    encServices = lib.mkOption {
      type = listOf attrs;
      description = "Services in the environment as provided by the ENC.";
    };

  };

  config = with lib; {

    environment.etc = optionalAttrs
      (hasAttrByPath ["parameters" "directory_secret"] cfg.enc)
      {
        "directory.secret".text = cfg.enc.parameters.directory_secret;
        "directory.secret".mode = "0600";
      };

    flyingcircus = {
      enc =
        mkDefault (fclib.jsonFromFile cfg.encPath "{}");
      encAddresses.srv =
        mkDefault (fclib.jsonFromFile cfg.encAddressesPath.srv "[]");
      encServices =
        mkDefault (fclib.jsonFromFile cfg.encServicesPath "[]");
      encServiceClients =
        mkDefault (fclib.jsonFromFile cfg.encServiceClientsPath "[]");
      systemState =
        mkDefault (fclib.jsonFromFile cfg.systemStatePath "{}");
    };

  };
}
