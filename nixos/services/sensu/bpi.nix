{ config, lib, pkgs, ... }:

with builtins;

let
  conf = config.flyingcircus.services;
in {
  options = with lib; {
    flyingcircus.services.sensuBpi = {
      enable = mkEnableOption "Sensu-bpi service";
      mail = mkOption {
        type = types.str;
        default = "E-MAIL";
        description = ''
            Mail address sensu-bpi sends its warning messeges to
        '';
      };
    };
  };

  config = lib.mkIf (conf.sensuBpi.enable) {
    environment = {
      systemPackages = with pkgs; [ fc.sensu-bpi ];
    };

    systemd.services.sensu-bpi = {
      description = "Sensu-bpi";
      serviceConfig = {
        Restart = "always";
        Type = "simple";
      };
      wantedBy = [ "multi-user.target" ];
      after = [ "sensu-client.service" ];
      script = "${pkgs.fc.sensu-bpi}/bin/fc.sensu-bpi ${conf.sensuBpi.mail}";
    };
  };
}
