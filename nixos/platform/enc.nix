{ config, lib, ... }:

let
  cfg = config.flyingcircus;

  fclib = config.fclib;

  enc =
    builtins.fromJSON (fclib.configFromFile
      cfg.enc_path
      (fclib.configFromFile "/etc/nixos/enc.json" "{}"));

  enc_addresses.srv = fclib.jsonFromFile cfg.enc_addresses_path.srv "[]";

  enc_services = fclib.jsonFromFile cfg.enc_services_path "[]";

  enc_service_clients = fclib.jsonFromFile cfg.enc_service_clients_path "[]";

  system_state = fclib.jsonFromFile cfg.system_state_path "{}";

  userdata = fclib.jsonFromFile cfg.userdata_path "[]";

  permissionsdata = fclib.jsonFromFile cfg.permissions_path "[]";

  admins_group_data = fclib.jsonFromFile cfg.admins_group_path "{}";

in
{
  options = with lib.types;
  {

    flyingcircus.enc = lib.mkOption {
      default = null;
      type = nullOr attrs;
      description = "Data from the external node classifier.";
    };

    flyingcircus.load_enc = lib.mkOption {
      default = true;
      type = bool;
      description = "Automatically load ENC data?";
    };

    flyingcircus.enc_path = lib.mkOption {
      default = "/etc/nixos/enc.json";
      type = string;
      description = "Where to find the ENC json file.";
    };

    flyingcircus.enc_addresses.srv = lib.mkOption {
      default = enc_addresses.srv;
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

    flyingcircus.enc_addresses_path.srv = lib.mkOption {
      default = /etc/nixos/addresses_srv.json;
      type = path;
      description = "Where to find the address list json file.";
    };

    flyingcircus.system_state = lib.mkOption {
      default = {};
      type = attrs;
      description = "The current system state as put out by fc-manage";
    };

    flyingcircus.system_state_path = lib.mkOption {
      default = /etc/nixos/system_state.json;
      type = path;
      description = "Where to find the system state json file.";
    };

    flyingcircus.enc_services = lib.mkOption {
      default = [];
      type = listOf attrs;
      description = "Services in the environment as provided by the ENC.";
    };

    flyingcircus.enc_services_path = lib.mkOption {
      default = /etc/nixos/services.json;
      type = path;
      description = "Where to find the ENC services json file.";
    };

    flyingcircus.enc_service_clients = lib.mkOption {
      default = [];
      type = listOf attrs;
      description = ''
        Service clients in the environment as provided by the ENC.
      '';
    };

    flyingcircus.enc_service_clients_path = lib.mkOption {
      default = /etc/nixos/service_clients.json;
      type = path;
      description = "Where to find the ENC service clients json file.";
    };

    flyingcircus.userdata_path = lib.mkOption {
      default = /etc/nixos/users.json;
      type = path;
      description = ''
        Where to find the user json file.
      '';
    };

    flyingcircus.userdata = lib.mkOption {
      default = userdata;
      type = listOf attrs;
      description = "All users local to this system.";
    };

    flyingcircus.permissions_path = lib.mkOption {
      default = /etc/nixos/permissions.json;
      type = path;
      description = ''
        Where to find the permissions json file.
      '';
    };

    flyingcircus.permissionsdata = lib.mkOption {
      default = permissionsdata;
      type = listOf attrs;
      description = "All permissions known on this system.";
    };

    flyingcircus.admins_group_path = lib.mkOption {
      default = /etc/nixos/admins.json;
      type = path;
      description = ''
        Where to find the admins group json file.
      '';
    };

    flyingcircus.admins_group_data = lib.mkOption {
      default = admins_group_data;
      type = attrs;
      description = "Members of ths admins group.";
    };

  };

}
