{ config, lib, pkgs, ... }:

with builtins;

let
  roles = config.flyingcircus.roles;

in
{
  options = {
    flyingcircus.roles.mailout = {
      # Mailout is considered to be included in the webgateway, but only
      # sometimes required. So it's a separate role, which is not a billable
      # component.
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable the Flying Circus mailserver out role and configure
          mailout on all nodes in this RG/location.
        '';
      };
    };
  };

  # `mailserver` is a full-featured mail solution while `mailout` just
  # configures SMTP sending serivces for its RG.
  config = {
    flyingcircus.services.ssmtp.enable =
      !(roles.mailserver.enable || roles.mailout.enable);
  };
}

