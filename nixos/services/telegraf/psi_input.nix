{ pkgs, ... }:
{
  flyingcircus.services.telegraf.inputs = {
    exec = [{
      commands = [ "${pkgs.fc.telegraf-collect-psi}/bin/collect_psi" ];
      timeout = "10s";
      data_format = "json";
      json_name_key = "name";
      tag_keys = ["period" "extent"];
    }];
  };
}
