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

  fqdn = net.hostName + (
    lib.optionalString (net.domain != null) ".${net.domain}");

in {
  options.flyingcircus.services.nullmailer.enable = lib.mkEnableOption ''
    Simple mail relay to the next mail server
  '';

  config = lib.mkIf (config.flyingcircus.services.nullmailer.enable &&
                     mailoutService != null) {
    services.nullmailer = {
      enable = true;
      config = {
        me = fqdn;
        adminaddr = "root@${mailoutService}";
        remotes = "${mailoutService} smtp port=25";
      };
    };
  };
}
