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

  mailout = mailoutService + (
    lib.optionalString (net.domain != null) ".${net.domain}");

in {
  options.flyingcircus.services.ssmtp.enable = lib.mkEnableOption ''
    Simple mail relay to the next mail server
  '';

  config = lib.mkIf (config.flyingcircus.services.ssmtp.enable &&
                     mailoutService != null) {
    services.ssmtp = {
      enable = true;
      hostName = mailout;
      root = "root@${mailout}";
    };
  };
}
