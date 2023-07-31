{ lib, config, pkgs, ... }:

with lib;

let
  cfg = config.flyingcircus;
  fclib = config.fclib;
  enc_services = fclib.jsonFromFile cfg.enc_services_path "[]";
  nixpkgsConfig = import ../../nixpkgs-config.nix;
  additionalModules = path:
    if builtins.pathExists path
    then
      map
        (name: "${path}/${name}")
        (filter
          (fn: lib.hasSuffix ".nix" fn)
          (lib.attrNames (builtins.readDir path)))
    else [];

in {
  imports = [
    ./acme.nix
    ./agent.nix
    ./audit.nix
    ./auditbeat.nix
    ./beats.nix
    ./filebeat.nix
    ./enc.nix
    ./firewall.nix
    ./journalbeat.nix
    ./collect-garbage.nix
    ./ipmi.nix
    ./kernel.nix
    ./monitoring.nix
    ./network.nix
    ./packages.nix
    ./shell.nix
    ./static.nix
    ./syslog.nix
    ./systemd.nix
    ./upgrade.nix
    ./users.nix
  ] ++
    (additionalModules "/etc/nixos/enc-configs") ++
    (additionalModules "/etc/local/nixos");

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

    flyingcircus.allowedUnfreePackageNames = mkOption {
      type = listOf str;
      description = ''
        Names of packages that are allowed to be used regardless of their
        license. Nix by default denies using packages with licenses considered
        "unfree" by nixpkgs. Note that unfree packages are not pre-built by
        cache.nixos.org and have to be pre-built by our hydra.flyingcircus.io
        (triggered by a NixOS test, defined in pkgs/overlay.nix or listed in
        release/default.nix includedPkgNames). Otherwise, it will be built
        directly on the machine using the package.
      '';
      default = [];
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

    flyingcircus.hostRgwAddress = mkOption {
      default = null;
      type = with types; nullOr str;
      description = ''
        IP address for the radosgw object storage proxy running on the
        virtualization host on port 7480. It allows VMs to access the
        S3(-compatible) storage via the fast storage network.

        This is the same as the `rgw.local` entry in `/etc/hosts`. Value is set if the
        machine is a virtual machine, null otherwise.
      '';
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
            type = types.path;
          };

          user = mkOption {
            default = "root";
            description = ''
              Name of the user owning the config directory,
              typically the name of the service or root.
            '';
            type = types.str;
          };

          group = mkOption {
            default = "service";
            description = "Name of the group.";
            type = types.str;
          };

          permissions = mkOption {
            default = "02775";
            description = ''
              Directory permissions.
              By default, owner and group can write to the directory and the
              sticky bit is set.
            '';
            type = types.str;
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

    flyingcircus.platform = {
      version = mkOption {
        readOnly = true;
        default = "22.11";
      };

      editions = mkOption {
        readOnly = true;
        description = ''
          Documented branches of this platform version.
        '';
        default = [ "fc-22.11-production" "fc-22.11-staging" "fc-22.11-dev" ];
      };
    };

    flyingcircus.passwordlessSudoRules = mkOption {
      description = ''
        Works like security.sudo.extraRules, but sets passwordless mode and
        places rules after rules with default order number (uses mkOrder 1100).
      '';

      default = [];
    };

    flyingcircus.stateVersionFile = mkOption {
      type = types.path;
      default = "/etc/local/nixos/state_version";
    };
  };

  config = {

    boot = {
      consoleLogLevel = mkDefault 7;

      initrd.kernelModules = [
        "bfq"
      ];

      kernelParams = [
        # Crash management
        "panic=1"
        "boot.panic_on_fail"

        # Output management
        "systemd.journald.forward_to_console=no"
        "systemd.log_target=kmsg"
      ];

      kernel.sysctl."vm.swappiness" = mkDefault 1;

      loader.timeout = 3;
    };

    environment.systemPackages = with pkgs; [
      fc.userscan
      dmidecode
    ];

    i18n.supportedLocales = [
      "all"
    ];

    # make the image smaller
    sound.enable = mkDefault false;
    documentation.dev.enable = mkDefault false;
    documentation.doc.enable = mkDefault false;
    # reduce build time
    documentation.nixos.enable = mkDefault false;

    nix = {
      nixPath = [
        "/nix/var/nix/profiles/per-user/root/channels/nixos"
        "/nix/var/nix/profiles/per-user/root/channels"
        "nixos-config=/etc/nixos/configuration.nix"
      ];

      extraOptions = ''
        keep-outputs = true
        fallback = true
        http-connections = 2
        log-lines = 25
        extra-experimental-features = nix-command flakes
      '';

      settings = {
        substituters = lib.mkOverride 90 [
          "https://cache.nixos.org"
          "https://s3.whq.fcio.net/hydra"
          "https://hydra.flyingcircus.io"
        ];

        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "flyingcircus.io-1:Rr9CwiPv8cdVf3EQu633IOTb6iJKnWbVfCC8x8gVz2o="
        ];
      };
    };

    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem
        (lib.getName pkg)
        config.flyingcircus.allowedUnfreePackageNames;

    nixpkgs.config.permittedInsecurePackages = nixpkgsConfig.permittedInsecurePackages;

    environment.etc."local/nixos/README.txt".text = ''
      To add custom NixOS config, create *.nix files here.
      here. These files must define a NixOS module.
      See `custom.nix.example` for the basic structure.
    '';

    environment.etc."local/nixos/custom.nix.example".text = ''
      { pkgs, lib, ... }:
      {
        environment.systemPackages = with pkgs; [
        ];
      }
    '';

    environment.etc."fcio_environment_name".text = config.flyingcircus.enc.parameters.environment or "";

    flyingcircus = {
      enc_services = enc_services;
      logrotate.enable = true;
      agent.collect-garbage = true;
      inherit (nixpkgsConfig) allowedUnfreePackageNames;
      services.sensu-client.mutedSystemdUnits = [ "logrotate.service" ];
    };

    # implementation for flyingcircus.passwordlessSudoRules
    security.sudo.extraRules = let
      nopasswd = [ "NOPASSWD" ];
      addPasswordOption = c:
        if builtins.typeOf c == "string"
        then { command = c; options = nopasswd; }
        else c // { options = (c.options or []) ++ nopasswd; };

      in
      lib.mkOrder
        1100
        (map
          (rule: rule // { commands = (map addPasswordOption rule.commands); })
          config.flyingcircus.passwordlessSudoRules);

    security.dhparams.enable = true;

    services = {
      # upstream uses cron.enable = mkDefault ... (prio 1000), mkPlatform
      # overrides it
      cron.enable = fclib.mkPlatform true;

      fail2ban.enable = fclib.mkPlatform true;
      fail2ban.ignoreIP =
        [
          # loopback
          "127.0.0.1/8"
          "::1"

          # rfc1918 addresses
          "10.0.0.0/8"
          "172.16.0.0/12"
          "192.168.0.0/16"
        ] ++
        cfg.static.firewall.trusted ++
        (flatten
          (builtins.map (v: builtins.attrNames v.networks)
            (builtins.attrValues (attrByPath [ "parameters" "interfaces" ] {} cfg.enc))));

      nscd.enable = true;
      openssh.enable = fclib.mkPlatform true;
      openssh.kbdInteractiveAuthentication = false;
      openssh.passwordAuthentication = false;

      telegraf.enable = mkDefault true;

      timesyncd.servers =
        let
          loc = attrByPath [ "parameters" "location" ] "" cfg.enc;
        in
        attrByPath [ "static" "ntpServers" loc ] [ "pool.ntp.org" ] cfg;
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

      wrapInSubshell = with fclib; text: "(\n" + text + "\n)";

      wrapActivationScript = value:
        if builtins.isAttrs value
        then value // { text = (wrapInSubshell value.text); }
        else wrapInSubshell value;

      # prefix our activation scripts with "fc-" and run them in a subshell
      fromActivationScripts = lib.mapAttrs'
        (name: value: lib.nameValuePair ("fc-" + name) (wrapActivationScript value))
        cfg.activationScripts;

    in fromCfgDirs // fromActivationScripts;

    system.stateVersion =
      if pathExists cfg.stateVersionFile
      then fileContents cfg.stateVersionFile
      else "22.11";

    systemd = {
      tmpfiles.rules = [
        # d instead of r to a) respect the age rule and b) allow exclusion
        # of fc-data to avoid killing the seeded ENC upon boot.
        "d /etc/current-config"  # used by various FC roles
        "d /etc/local/nixos 2775 root service"
        "d /srv 0755"
      ];

      ctrlAltDelUnit = "poweroff.target";
      extraConfig = ''
        RuntimeWatchdogSec=60
      '';
    };


    time.timeZone = fclib.mkPlatform
      (attrByPath [ "parameters" "timezone" ] "UTC" config.flyingcircus.enc);

  };
}
