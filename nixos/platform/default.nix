{ lib, config, ... }:

with lib;
{
  imports = [
    ./enc.nix
    ./network.nix
    ./packages.nix
    ./shell.nix
    ./static.nix
    ./users.nix
  ];

  config = {

    boot.loader.timeout = 3;

    # make the image smaller
    sound.enable = mkDefault false;
    documentation.enable = mkDefault false;
    services.nixosManual.enable = mkDefault false;

    nix = {
      nixPath = [
        "/nix/var/nix/profiles/per-user/root/channels/nixos"
        "/nix/var/nix/profiles/per-user/root/channels"
        "nixos-config=/etc/nixos/configuration.nix"
      ];

      binaryCaches = [
        https://cache.nixos.org
        https://hydra.flyingcircus.io
      ];

      binaryCachePublicKeys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "flyingcircus.io-1:Rr9CwiPv8cdVf3EQu633IOTb6iJKnWbVfCC8x8gVz2o="
      ];

      extraOptions = ''
        fallback = true
      '';
    };

    services.openssh.enable = true;

    i18n.supportedLocales = [ (config.i18n.defaultLocale + "/UTF-8") ];

    system.stateVersion = mkDefault "18.09";

  };
}
