{ config, lib, ... }:

with builtins;

let
  fclib = config.fclib;
  net = config.networking;

  mailoutService =
    let services =
      (fclib.listServiceAddresses "mailserver-mailout" ++
       fclib.listServiceAddresses "mailstub-mailout" ++
       fclib.listServiceAddresses "mailout-mailout");
    in
      if services == [] then null else head services;

in {
  options.flyingcircus.services.ssmtp.enable = lib.mkEnableOption ''
    Simple mail relay to the next mail server
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
