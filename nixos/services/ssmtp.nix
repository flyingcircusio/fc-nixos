{ config, lib, ... }:

with builtins;

let
  fclib = config.fclib;
  net = config.networking;

  mailoutService =
    let services =
      # Prefer mailout. This would allow splitting in and out automagically.
      (fclib.listServiceAddresses "mailout-mailout" ++
       fclib.listServiceAddresses "mailserver-mailout");
    in
      if services == [] then null else head services;

in
{
  options.flyingcircus.services.ssmtp.enable = lib.mkEnableOption ''
    Dumb mail relay to the next 'mailout' server
  '';

  config = lib.mkIf (config.flyingcircus.services.ssmtp.enable &&
                     mailoutService != null) {
    networking.defaultMailServer = {
      directDelivery = true;
      domain =
        lib.optionalString (net.domain != null) "${net.hostName}.${net.domain}";
      hostName = mailoutService;
      root = "root@${mailoutService}";
    };
  };
}
