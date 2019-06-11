{ lib, config, ... }:

with lib;

let 
  cfg = config.flyingcircus;
  enc_services = fclib.jsonFromFile cfg.enc_services_path "[]";
  fclib = config.fclib;

in {
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

  options = with lib.types; {
    flyingcircus.roles.generic.enable =
      mkEnableOption "Generic role, which does nothing";

    flyingcircus.enc_services = mkOption {
      default = [];
      type = listOf attrs;
      description = "Services in the environment as provided by the ENC.";
    };

    flyingcircus.enc_services_path = mkOption {
      default = /etc/nixos/services.json;
      type = path;
      description = "Where to find the ENC services json file.";
    };

  };

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

    flyingcircus.enc_services = enc_services;

    services = {
      # reduce build time
      nixosManual.enable = mkDefault false;

      # upstream uses cron.enable = mkDefault ... (prio 1000),
      # so we must go a bit lower to set a new default
      cron.enable = mkOverride 900 true; 

      nscd.enable = true;
      openssh.enable = mkDefault true;
    };

    systemd.tmpfiles.rules = [
      # d instead of r to a) respect the age rule and b) allow exclusion
      # of fc-data to avoid killing the seeded ENC upon boot.
      "d /etc/current-config"  # used by various FC roles
      "d /srv 0755"
      "d /tmp 1777 root root 3d"
      "d /var/tmp 1777 root root 7d"
      # remove old (pre-16.09) setuid wrappers first reboot after upgrade
      "R! /var/setuid-wrappers"
    ];

    time.timeZone =
      attrByPath [ "parameters" "timezone" ] "UTC" config.flyingcircus.enc;

  };
}
