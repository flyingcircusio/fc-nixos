{
  pkgs,
  config,
  lib,
  ...
}:

let
  domainSuffix = if (config.networking.domain != null) then ".${config.networking.domain}" else "";
in
{

  environment.systemPackages = [ pkgs.mailutils ];

  environment.etc."mailutils.conf".text = ''
    address {
        email-domain ${config.networking.hostName}${domainSuffix};
    }
  '';

}
