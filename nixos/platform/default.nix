{ lib, config, ... }:

with lib;
{
  imports = [
    ./agent.nix
    ./enc.nix
    ./firewall.nix
    ./garbagecollect
    ./monitoring.nix
    ./network.nix
    ./packages.nix
    ./shell.nix
    ./static.nix
    ./systemd.nix
    ./users.nix
  ];

  options.flyingcircus.roles.generic.enable =
    mkEnableOption "Generic role, which does nothing";

  config = {

    boot.loader.timeout = 3;

    # make the image smaller
    sound.enable = mkDefault false;
    documentation.dev.enable = mkDefault false;
    documentation.doc.enable = mkDefault false;

    i18n.supportedLocales = [ (config.i18n.defaultLocale + "/UTF-8") ];

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

    services = {
      # reduce build time
      nixosManual.enable = mkDefault false;

      nscd.enable = true;
      openssh.enable = mkDefault true;
    };

    systemd.tmpfiles.rules = [
      # d instead of r to a) respect the age rule and b) allow exclusion
      # of fc-data to avoid killing the seeded ENC upon boot.
      "d /tmp 1777 root root 3d"
      "d /var/tmp 1777 root root 7d"
      "d /srv"
      "z /srv 0755 root root"
    ];

    time.timeZone =
      attrByPath [ "parameters" "timezone" ] "UTC" config.flyingcircus.enc;

  };
}
