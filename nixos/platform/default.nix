{ lib, config, ... }:

with lib;
{
  imports = [
    ./network.nix
    ./static.nix
  ];

  config = {

    # make the image smaller
    sound.enable = mkDefault false;
    documentation.enable = mkDefault false;
    services.nixosManual.enable = mkDefault false;

    nix.nixPath = [
      "/nix/var/nix/profiles/per-user/root/channels/nixos"
      "/nix/var/nix/profiles/per-user/root/channels"
      "nixos-config=/etc/nixos/configuration.nix"
    ];

    services.openssh.enable = true;

    i18n.supportedLocales = [ (config.i18n.defaultLocale + "/UTF-8") ];

    system.stateVersion = mkDefault "18.09";

  };
}
