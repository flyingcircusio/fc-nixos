  { lib, config, pkgs, ...}:
  let
  cfg = config.flyingcircus.services.proftpd;
  renderSettings = settingsAttr: lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: val: "${name} ${val}")
    (lib.filterAttrs (_: v: v != null) settingsAttr)
  );
  vhostTypes = [ "ftp" "sftp" ];
  globalDefaults = {
      AllowOverwrite = "on";
      DefaultRoot = "~";  # restricts via chroot to home dir
      RequireValidShell = "off";
      Umask = "022";
    };
  vhost = {...}:{
    options = {
      type = lib.mkOption {
        type = lib.types.enum vhostTypes;
        description = "Sepcify what kind of VirtualHost this is, currently either \"ftp\" or \"sftp\"";
      };
      listen = {
        port = lib.mkOption {
          type = lib.types.port;
          description = "listening port of the Vhost";
        };
        #TODO: defaults from srv fclib, but done in role?
        addresses = lib.mkOption {
          type = with lib.types; listOf str;
          description = "FQDNs or IP addresses the vhost listens under, both v4 and v6";
        };
      };
      # if we ever support more or even freeform proftpd modules, this might need to be
      # reworked, but for now keeping it simple
      sftp = {
        hostKey = lib.mkOption {
          type = lib.types.str;
        };
      };
      ftp = {
        passivePorts = lib.mkOption {
          type = with lib.types; nullOr (listOf lib.types.port);
          default = null;
        };
      };
      settings = lib.mkOption {
        type = with lib.types; attrsOf str;
        description = ''Freeform additional configuration.
          Each settings attribute is rendered as a single line, concatenating
          attrName and attrValue with a space character.
          Pre-defined default attributes can be removed by setting their value
          to `null`.'';
        default = {};
      };
      extraConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          arbitrary freeform text block at the end of the vhost.
          For individual config options, please prefer `settings` where possible.
          extraConfig only exists for allowing to nest further text blocks into
          a vhost config.
          '';
      };
    };
  };
in
{
options.flyingcircus.services.proftpd = {
  enable = lib.mkEnableOption "ProFTPD FTP server";
  package = lib.mkOption {
    type = lib.types.package;
    default = pkgs.proftpd;
  };
  maxConnections = lib.mkOption {
    type = with lib.types; nullOr ints.positive;
    default = 100;
    description = ''Limits number of child processes that can be spawned and
    thus the number of maximum clients that can be served.
    In proftpd terminology, it sets `MaxInstances` and `MaxClients`.'';
  };
  # FIXME: current deployment uses workdir = "/srv/s-blackbee/deployment/work/proftpd";
  # FIXME: tmpfiles.d rule necessary?
  workdir = lib.mkOption {
    type = lib.types.path;
    default = "/var/lib/proftpd";
  };
  user = lib.mkOption {
    type = lib.types.str;
    description = ''After starting as root, the daemon drops to these user's
      privileges for the "server config" context.
      Also used as default for each vhost unless overriden.
    '';
    default = "nobody";
  };
  # TODO role: services
  group = lib.mkOption {
    type = lib.types.str;
    description = ''The daemon drops to these group
      privileges for the "server config" context.
      Also used as default for each vhost unless overriden.
    '';
    default = "nogroup";
  };
  globals = lib.mkOption {
    type = with lib.types; attrsOf str;
    description = ''Freeform config applied to all vhosts.
      Each settings attribute is rendered as a single line, concatenating
      attrName and attrValue with a space character.
      Pre-defined default attributes can be overriden individually and removed
      by setting their value to `null`.'';
    default = builtins.mapAttrs (_: v: lib.mkDefault v) globalDefaults;
    defaultText = lib.generators.toPretty { } globalDefaults;
  };
  vhosts = lib.mkOption {
    type = with lib.types; attrsOf (submodule vhost);
    description = ''
      A set of proftpd `VirtualHost` entries. Currently supports plain FTP and
      mod_sftp vhosts.
      Note that the attribute names are just of significance within the NixOS
      module system for having a reference name when overriding individual options,
      but are not rendered into the actual configuration.
      '';
  };
  # this is a workaround to be able to use the NixOS module system mkIf and
  # mkMerge capabilities to combine the freeform settings attributes with the
  # explicitly defined options into a single name space.
  mergedVhostSettings = lib.mkOption {
    internal = true;
    readOnly = true;
    type = with lib.types; listOf (attrsOf (either str (attrsOf str)));
    # insert the explicitly defined options into the freeform settings
    default = lib.mapAttrsToList (_: v: {
      listenAddresses = builtins.concatStringsSep " " v.listen.addresses;
      settings = lib.mkMerge [
        v.settings

        # directives independent of server type
        {
          Port = toString v.listen.port;
          User = lib.mkDefault cfg.user;
          Group = lib.mkDefault cfg.group;
          AuthOrder = lib.mkDefault "mod_auth_file.c mod_auth_unix.c";
          # ToDo: role
          #AuthUserFile = "${component.passwd_file.path}"; #FIXME
        }

        (lib.mkIf (v.ftp.passivePorts != null) {
          PassivePorts = lib.concatMapStringsSep " " v.passivePorts;
        })

        (lib.mkIf (v.type == "sftp") {
          SFTPEngine = "on";
          SFTPHostKey = v.sftp.hostKey;
          SFTPAuthMethods = lib.mkDefault "publickey password";
          SFTPAuthorizedUserKeys = lib.mkDefault "file:~/.sftp/authorized_keys";
          SFTPCompression = lib.mkDefault "delayed";
        })
        ];
      }) cfg.vhosts;
  };
  extraConfig = lib.mkOption {
    type = lib.types.lines;
    default = "";
    description = "arbitrary freeform text block at the end of the config file";
  };
};

config = let
  vhostConfigs = builtins.map (v: ''
    <VirtualHost ${v.listenAddresses}>
      ${renderSettings v.settings}
    </VirtualHost>
    '') cfg.mergedVhostSettings;
    # TODO for role/ fc service: global with setting a banner string including the hostname
    #ServerName "ProFTPD Server @${host.fqdn}"
  configFile = pkgs.writeText "proftpd.conf" ''
    ServerType standalone
    PidFile /run/proftpd.pid
    ${lib.optionalString (cfg.maxConnections != null) ''
      MaxClients ${toString cfg.maxConnections}
      MaxInstances ${toString (cfg.maxConnections + 1)}
    ''}
    DelayTable ${cfg.workdir}/delaytable
    ScoreboardFile ${cfg.workdir}/scoreboard

    # turn of the "server config"-defined server to rely solely on vhosts
    Port 0

    # This applies to the main listening process, individual vhosts can be set
    # to a separate user
    User ${cfg.user}
    Group ${cfg.group}

    <Global>
    ${renderSettings cfg.globals}
    </Global>

    # FIXME do we need this?
    #<Limit SITE_CHMOD>
    #    DenyAll
    #</Limit>

    ${builtins.concatStringsSep "\n" vhostConfigs}

    ${cfg.extraConfig}
  '';

  in
  {
  # TODO: assertions
  # require at least 1 vhost
  systemd.services.proftpd = {
    description = "Proftpd";
    wantedBy = [ "multi-user.target" ];
    # FIXME: can we reload instead?
    stopIfChanged = false;
    restartTriggers = [ configFile ];
    serviceConfig = {
      ExecStart = "${cfg.package}/bin/proftpd --nodaemon -c ${configFile}";
      # needs to start as root, but can re-bind later
      StateDirectory = "proftpd";
      Restart = "always";
    };
  };
  # FIXME: logging, logrotate?
  # FIXME: user management, auth helper package https://gitlab.flyingcircus.io/webdata/blackbee-frontend-batou/-/blob/master/components/proftpd/create_sftp_user?ref_type=heads
  # FIXME: service checks
  # FIXME firewall

  environment.etc."proftpd.conf".source = configFile;
  environment.systemPackages = [ cfg.package ];

  };
}
