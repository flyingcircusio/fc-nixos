{ lib, config, ... }:

with lib;

let 
  cfg = config.flyingcircus;
  fclib = config.fclib;
  enc_services = fclib.jsonFromFile cfg.enc_services_path "[]";

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

    flyingcircus.activationScripts = mkOption {
      description = ''
        This does the same as system.activationScripts, 
        but script / attribute names are prefixed with "fc-" automatically:

        flyingcircus.activationScripts.script-name becomes
        system.activationScripts.fc-script-name

        Dependencies specified with lib.stringAfter must include the prefix.
      '';
      default = {};
      # like in system.activationScripts, can be a string or a set (lib.stringAfter)
      type = types.attrsOf types.unspecified; 
    };

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

    flyingcircus.localConfigDirs = mkOption {
      description = ''
        Create a directory where local config files for a service can be placed.
        The attribute path, for example flyingcircus.localConfigDirs.myservice
        is echoed in the activation script for debugging purposes.

        Other activation scripts that need a local config dir
        can create a dependency on fc-local-config with stringAfter:

        flyingcircus.activationScripts.needsCfg = lib.stringAfter ["fc-local-config"] "script..."
      '';
      default = {};

      example = { myservice = { dir = "/etc/local/myservice"; user = "myservice"; }; };

      type = types.attrsOf (types.submodule {

        options = {

          dir = mkOption {
            description = "Path to the directory, typically starting with /etc/local.";
            type = types.string;
          };

          user = mkOption {
            default = "root";
            description = ''
              Name of the user owning the config directory,
              typically the name of the service or root.
            '';
            type = types.string;
          };

          group = mkOption {
            default = "service";
            description = "Name of the group.";
            type = types.string;
          };

          permissions = mkOption {
            default = "02775";
            description = ''
              Directory permissions.
              By default, owner and group can write to the directory and the sticky bit is set.
            '';
            type = types.string;
          };

        };

      });
    };

    flyingcircus.localConfigPath = mkOption {
      description = ''
        This option is only needed for tests.
        WARNING: Do not change this outside of tests, it will break stuff!

        The local config must be present at built time for some tests but
        the default path references /etc/local on the machine where the tests
        are run. This option can be used to set a path relative to the test 
        (path starting with ./ without double quotes) where the local config
        can be found. For example, custom firewall rules can be put into
        ./test_cfg/firewall/firewall.conf for testing.
      '';
      type = types.path;
      default = "/etc/local";
      example = ./test_cfg;
    };

    flyingcircus.roles.generic.enable =
      mkEnableOption "Generic role, which does nothing";

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

    # reduce build time
    documentation.nixos.enable = mkDefault false;

    services = {

      # upstream uses cron.enable = mkDefault ... (prio 1000), mkPlatform overrides it
      cron.enable = fclib.mkPlatform true; 

      nscd.enable = true;
      openssh.enable = mkDefault true;
    };

    system.activationScripts = let

      cfgDirs = cfg.localConfigDirs;

      snippet = name: ''
        # flyingcircus.localConfigDirs.${name}
        ${fclib.installDirWithPermissions { 
          inherit (cfgDirs.${name}) user group permissions dir; 
        }}
      '';

      # concat script snippets for all local config dirs
      cfgScript = lib.fold 
                    (name: acc: acc + "\n" + (snippet name)) 
                    ""
                    (lib.attrNames cfgDirs);

      fromCfgDirs = { 
        fc-local-config = lib.stringAfter ["users" "groups"] cfgScript; 
      };

      # prefix our activation scripts with "fc-"
      fromActivationScripts = lib.mapAttrs' 
                                (name: value: lib.nameValuePair ("fc-" + name) value) 
                                cfg.activationScripts;

    in fromCfgDirs // fromActivationScripts;

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
