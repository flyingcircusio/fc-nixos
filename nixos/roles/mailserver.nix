{ config, lib, pkgs, ... }:

with builtins;

let
  params = lib.attrByPath [ "parameters" ] {} config.flyingcircus.enc;
  fclib = config.fclib;
  roles = config.flyingcircus.roles;

  listenFe = fclib.listenAddresses "ethfe";

  # default domain should be changed to to fcio.net once #14970 is finished
  defaultHostname =
    if (params ? location &&
        lib.hasAttrByPath [ "interfaces" "fe" ] params &&
        (length listenFe > 0))
    then "${config.networking.hostName}.fe.${params.location}.gocept.net"
    else "${config.networking.hostName}.gocept.net";

in
{
  options = {

    flyingcircus.roles.mailserver = with lib; {
      # The mailserver role was/is thought to implement an entire mailserver,
      # and would be billed as component.

      enable = mkEnableOption ''
        Enable the Flying Circus mailserver out role and configure
        mailout on all nodes in this RG/location.
      '';

      hostname = mkOption {
        type = types.str;
        default = fclib.configFromFile
          /etc/local/postfix/myhostname defaultHostname;
        description = ''
          Set the FQDN the mail server announces in its SMTP dialogues. Must
          match forward and reverse DNS.
        '';
        example = "mail.project.example.com";
      };

      smtpBindAddresses = mkOption {
        type = with types; listOf str;
        default = listenFe;
        description = ''
          List of IP addresses for outgoing SMTP connections. If there is more
          than one address for any address family, only the first one will be
          used.
        '';
      };
    };

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

  # `mailserver` will grow into a full-featured mail solution some day while
  # `mailout` configures SMTP sending serivces for its RG.
  config = {
    flyingcircus.services.postfix.enable =
      (roles.mailserver.enable || roles.mailout.enable);

    flyingcircus.services.ssmtp.enable =
      !(roles.mailserver.enable || roles.mailout.enable);
  };
}
