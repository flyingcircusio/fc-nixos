{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.services.ceph;
  fclib = config.fclib;
  static = config.flyingcircus.static.ceph;
  public_network = head fclib.network.sto.v4.networks;
  location = config.flyingcircus.enc.parameters.location;
  resource_group = config.flyingcircus.enc.parameters.resource_group;
  fs_id = static.fsids.${location}.${resource_group};
  mons = lib.concatMapStringsSep ","
    (mon: "${head (lib.splitString "." mon.address)}.sto.${location}.ipv4.gocept.net")
    (fclib.findServices "ceph_mon-mon");
  inherit (fclib.ceph) expandCamelCaseAttrs expandCamelCaseSection;

  defaultGlobalSettings = {
    fsid = fs_id;

    publicNetwork = public_network;

    pidFile = "/run/ceph/$type-$id.pid";
    adminSocket = "/run/ceph/$cluster-$name.asok";

    # Needs to correspond with daemon startup ulimit
    maxOpenFiles = 262144;

    osdPoolDefaultMinSize = 2;
    osdPoolDefaultSize = 3;

    osdPoolDefaultPgNum = 64;
    osdPoolDefaultPgpNum = 64;

    setuserMatchPath = "/srv/ceph/$type/ceph-$id";

    debugFilestore = 4;
    debugMon = 4;
    debugOsd = 4;
    debugJournal = 4;
    debugThrottle = 4;

    monCompactOnStart = true;     # Keep leveldb small
    monHost = mons;
    monOsdDownOutInterval = 900;  # Allow 15 min for reboots to happen without backfilling.
    monOsdNearfullRatio = .9;

    monData = "/srv/ceph/mon/$cluster-$id";
    monOsdAllowPrimaryAffinity = true;
    monPgWarnMaxObjectSkew = 30;

    mgrData = "/srv/ceph/mgr/$cluster-$id";
  } // lib.optionalAttrs (cfg.cluster_network != null) { clusterNetwork = cfg.cluster_network;}
  ;

  defaultClientSettings = {
    logFile = "/var/log/ceph/client.log";
    rbdCache = true;
    rbdDefaultFormat = 2;
    # The default default is 61, which enables all the new fancy features of jewel
    # which we are a) scared of due to performance concerns and because b)
    # we are not prepared to handle locking in this weird way ...
    rbdDefaultFeatures = 1;
    adminSocket = "/run/ceph/rbd-$pid-$cctid.asok";
  };


in
{
  options = {

    flyingcircus.services.ceph = {
      # legacy config for pre-Nautilus hosts (and migration to it), default value will
      # already be served by structured settings instead
      config = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          Global config of the Ceph config file. Will be used
          for all Ceph daemons and binaries.
          Starting from Ceph Nautilus on, this is deprecated.
        '';
      };
      extraConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          Extra config in the [global] section.
        '';
      };
      extraSettings = lib.mkOption {
        # TODO: explicitly factoring out certain config options, like done in the
        # nixpkgs upstream ceph module, might allow for better type checking
        type = with lib.types; attrsOf (oneOf [ str int float bool ]);
        default = {};   # defaults are provided in the config section with a lower priority
        description = ''
          Global config of the Ceph config file. Will be used
          for all Ceph daemons and binaries.
          Can override existing default setting values. Configuration keys like `mon osd full ratio`''
          + '' can alternatively be written in camelCase as `monOsdFullRatio`.
        '';
      };
      extraSettingsSections = lib.mkOption {
        # serves as interface for other Ceph roles and services, these can then add additional INI sections to ceph.conf
        type = with lib.types; attrsOf (attrsOf (oneOf [ bool int str float ]));
        default = { };
        description = "Additional config sections of ceph.conf, for use by components and roles.";
      };
      cluster_network = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      fc-ceph = {
        settings = lib.mkOption {
          type = with lib.types; attrsOf (attrsOf (oneOf [ bool int str package ]));
          default = { };
          description = "Configuration for the fc-ceph utility, will be turned into the contents of /etc/ceph/fc-ceph.conf";
        };
      };

      client = {
        enable = lib.mkEnableOption "Ceph client";

        cephRelease = lib.mkOption {
          type = fclib.ceph.highestCephReleaseType;
          description = "Ceph release series that the main package belongs to. "
            + "This option behaves special in a way that, if defined multiple times, the latest release name will be chosen.";
          default = fclib.ceph.defaultRelease;
        };

        package = lib.mkOption {
          type = lib.types.package;
          description = "Main ceph package to be used on the system and to be put into PATH. "
            + "The package set must belong to the release series defined in the `cephRelease` option. "
            + "Only modify if really necessary, otherwise the default ceph package from the defined series is used.";
          default =  fclib.ceph.releasePkgs.${cfg.client.cephRelease}.ceph-client;
        };

        # legacy config for pre-Nautilus hosts (and migration to it), default value will
        # already be served by structured settings instead
        config = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = ''
            Contents of the Ceph config file for clients.
            Starting from Ceph Nautilus on, this is deprecated.
          '';
        };
        extraSettings = lib.mkOption {
          type = with lib.types; attrsOf (oneOf [ str int float bool ]);
          default = {};   # defaults are provided in the config section with a lower priority
          description = ''
            Client config of the Ceph config file. Will be used
            for all Ceph clients, including rbd.
            Can override existing default setting values. Configuration keys like `mon osd full ratio` can alternatively be written in camelCase as `monOsdFullRatio`.
            '';
        };
      };
    };
  };

  config = lib.mkIf cfg.client.enable {

    assertions = [
      {
        assertion = (cfg.client.package.codename == cfg.client.cephRelease);
        message = "The ceph package set for this ceph client service must be of the same release series as defined in `cephRelease`";
      }
      {
        assertion = (cfg.extraSettings != {} || cfg.client.extraSettings != {}
          -> cfg.config == "" && cfg.extraConfig == "" && cfg.client.config == "");
          message = "Mixing the configuration styles (extra)Config and (extra)Settings is unsupported, please use either plaintext config or structured settings for ceph.";
      }
    ];

    # config file to be read by fc-ceph
    environment.etc."ceph/fc-ceph.conf".text = lib.generators.toINI { } cfg.fc-ceph.settings;

    # build a default binary path for fc-ceph
    flyingcircus.services.ceph.fc-ceph.settings.default = {
      release = cfg.client.cephRelease;
      path = fclib.ceph.fc-ceph-path cfg.client.package;
    };
    environment.systemPackages = [ cfg.client.package ];

    boot.kernelModules = [ "rbd" ];

    systemd.tmpfiles.rules = [
      "d /run/ceph - root - - -"
      "d /var/log/ceph 0755 root - - -"
    ];

    services.udev.extraRules =
      if fclib.ceph.releaseAtLeast "nautilus" cfg.client.cephRelease
      then builtins.readFile "${cfg.client.package}/etc/udev/50-rbd.rules"
      else
      ''
        KERNEL=="rbd[0-9]*", ENV{DEVTYPE}=="disk", PROGRAM="${cfg.client.package}/bin/ceph-rbdnamer %k", SYMLINK+="rbd/%c{1}/%c{2}"
        KERNEL=="rbd[0-9]*", ENV{DEVTYPE}=="partition", PROGRAM="${cfg.client.package}/bin/ceph-rbdnamer %k", SYMLINK+="rbd/%c{1}/%c{2}-part%n"
      '';

    environment.etc."ceph/ceph.conf".text = let
      throwDeprecationWarning = lib.warnIf (fclib.ceph.releaseAtLeast "nautilus" cfg.client.cephRelease)
        ("Configuring ceph via plaintext `config` and `extraConfig` is deprecated since "
        + "the Nautilus role, please switch to `extraSettings`.");
      mergedSettings = (
        lib.recursiveUpdate
          (expandCamelCaseSection cfg.extraSettingsSections)
          # make these global settings take precedence over those provided by extraSettingsSections.
          # camelCase names need to be expanded *before* merging, to ensure that keys are in equal formats.
          (
            { global = lib.recursiveUpdate (expandCamelCaseAttrs defaultGlobalSettings) (expandCamelCaseAttrs cfg.extraSettings); }
            // { client = lib.recursiveUpdate (expandCamelCaseAttrs defaultClientSettings) (expandCamelCaseAttrs cfg.client.extraSettings); }
          )
      );
      globalConfig = (if (cfg.config != "")
        # prefer old plaintext config if it has been customised, but possibly throw warning
        then throwDeprecationWarning (cfg.config + "\n" + cfg.extraConfig)
        else lib.generators.toINI { } { global = mergedSettings.global; })
        + (if (cfg.extraConfig != "") then throwDeprecationWarning ("\n" + cfg.extraConfig) else "");
      clientConfig = if (cfg.client.config != "")
        then throwDeprecationWarning cfg.client.config
        else lib.generators.toINI { } {client = mergedSettings.client;};
      otherConfig = lib.generators.toINI { } (
        lib.filterAttrs (k: _: ! builtins.elem k [ "global" "client"] ) mergedSettings
        );
    in
      (globalConfig + "\n" + clientConfig + "\n" + otherConfig);

    environment.variables.CEPH_ARGS = fclib.mkPlatform "--id ${config.networking.hostName}";

    flyingcircus.activationScripts.ceph-client-keyring = ''
      ${pkgs.fc.cephWith cfg.client.package}/bin/fc-ceph keys generate-client-keyring
    '';

    services.logrotate.extraConfig = ''
      /var/log/ceph/client.log {
          rotate 30
          create 0644 root adm
          copytruncate
      }
    '';

  };

}
