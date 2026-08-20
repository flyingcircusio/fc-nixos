# Taken from NixOS 22.11, see pkgs/solr/COPYING.md
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let

  cfg = config.services.solr;

  newCli = lib.versionAtLeast cfg.package.version "10";
in

{
  options = {
    services.solr = {
      enable = mkEnableOption "Solr";

      package = mkOption {
        type = types.package;
        default = pkgs.solr;
        defaultText = literalExpression "pkgs.solr";
        description = "Which Solr package to use.";
      };

      port = mkOption {
        type = types.port;
        default = 8983;
        description = "Port on which Solr is ran.";
      };

      stateDir = mkOption {
        type = types.path;
        default = "/var/lib/solr";
        description = "The solr home directory containing config, data, and logging files.";
      };

      extraJavaOptions = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Extra command line options given to the java process running Solr.";
      };

      user = mkOption {
        type = types.str;
        default = "solr";
        description = "User under which Solr is ran.";
      };

      group = mkOption {
        type = types.str;
        default = "solr";
        description = "Group under which Solr is ran.";
      };
    };
  };

  config = mkIf cfg.enable {

    environment.systemPackages = [ cfg.package ];

    systemd.services.solr = {
      after = [
        "network.target"
        "remote-fs.target"
        "nss-lookup.target"
        "systemd-journald-dev-log.socket"
      ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        SOLR_HOME = "${cfg.stateDir}/data";
        LOG4J_PROPS = "${cfg.stateDir}/log4j2.xml";
        SOLR_LOGS_DIR = "${cfg.stateDir}/logs";
        ${if newCli then "SOLR_PORT_LISTEN" else "SOLR_PORT"} = "${toString cfg.port}";
      };
      path = with pkgs; [
        gawk
        procps
      ];
      preStart = ''
        mkdir -p "${cfg.stateDir}/data";
        mkdir -p "${cfg.stateDir}/logs";

        if ! test -e "${cfg.stateDir}/data/solr.xml"; then
          install -D -m0640 ${cfg.package}/server/solr/solr.xml "${cfg.stateDir}/data/solr.xml"
          install -D -m0640 ${cfg.package}/server/solr/zoo.cfg "${cfg.stateDir}/data/zoo.cfg"
        fi

        if ! test -e "${cfg.stateDir}/log4j2.xml"; then
          install -D -m0640 ${cfg.package}/server/resources/log4j2.xml "${cfg.stateDir}/log4j2.xml"
        fi
      '';

      serviceConfig = {
        User = cfg.user;
        Group = cfg.group;
        ExecStart =
          let
            optionFormat = optionName: {
              option = if newCli && lib.stringLength optionName > 1 then "--${optionName}" else "-${optionName}";
              sep = null;
              explicitBool = false;
            };
            args = lib.cli.toCommandLineShell optionFormat {
              foreground = true;
              ${if newCli then "jvm-opts" else "addlopts"} = lib.optional (cfg.extraJavaOptions != [ ]) (
                concatStringsSep " " cfg.extraJavaOptions
              );
              user-managed = newCli;
            };
          in
          "${lib.getExe cfg.package} start ${args}";

        ExecStop = "${lib.getExe cfg.package} stop";
        LimitNOFILE = 65000;
        LimitNPROC = 65000;
      };
    };

    users.users = optionalAttrs (cfg.user == "solr") {
      solr = {
        group = cfg.group;
        home = cfg.stateDir;
        createHome = true;
        uid = config.ids.uids.solr;
      };
    };

    users.groups = optionalAttrs (cfg.group == "solr") {
      solr.gid = config.ids.gids.solr;
    };

  };

}
