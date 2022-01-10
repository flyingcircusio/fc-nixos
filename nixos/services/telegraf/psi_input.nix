{ pkgs, lib, config, ... }:
let 
  inherit (lib) types;
  psi_cgroup_regex = lib.concatStringsSep "|" config.flyingcircus.services.telegraf.psi_cgroup_regex;
in {
  options.flyingcircus.services.telegraf.psi_cgroup_regex = lib.mkOption {
    type = types.listOf types.str;
    default = [ ];
  };
  config = {
    flyingcircus.services.telegraf.psi_cgroup_regex = [ "^/system.slice$" "^/system.slice.*service$" "^/user.slice$" ];
    flyingcircus.services.telegraf.inputs = {
      exec = [{
        commands = [ "${pkgs.fc.telegraf-collect-psi}/bin/collect_psi" ];
        timeout = "10s";
        data_format = "json";
        json_name_key = "name";
        tag_keys = ["period" "extent"];
      }
      {
        commands = [ "${pkgs.fc.telegraf-collect-psi}/bin/collect_psi_cgroups --regex ${psi_cgroup_regex}" ];
        timeout = "10s";
        data_format = "json";
        json_name_key = "name";
        tag_keys = ["period" "extent" "cgroup"];
      }];
    };
  };
}
