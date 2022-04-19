{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.opensearch;

  opensearchConfig = ''
    network.host: ${cfg.listenAddress}
    cluster.name: ${cfg.cluster_name}
    ${lib.optionalString cfg.single_node "discovery.type: single-node"}
    ${lib.optionalString cfg.single_node "gateway.auto_import_dangling_indices: true"}

    http.port: ${toString cfg.port}
    transport.port: ${toString cfg.tcp_port}

    ${cfg.extraConf}
  '';

  configDir = cfg.dataDir + "/config";

  opensearchYml = pkgs.writeTextFile {
    name = "opensearch.yml";
    text = opensearchConfig;
  };

  loggingConfigFilename = "log4j2.properties";
  loggingConfigFile = pkgs.writeTextFile {
    name = loggingConfigFilename;
    text = cfg.logging;
  };

in
{

  ###### interface

  options.services.opensearch = {
    enable = mkOption {
      description = "Whether to enable opensearch.";
      default = false;
      type = types.bool;
    };

    package = mkOption {
      description = "opensearch package to use.";
      default = pkgs.opensearch;
      defaultText = literalExpression "pkgs.opensearch";
      type = types.package;
    };

    listenAddress = mkOption {
      description = "opensearch listen address.";
      default = "127.0.0.1";
      type = types.str;
    };

    port = mkOption {
      description = "opensearch port to listen for HTTP traffic.";
      default = 9200;
      type = types.int;
    };

    tcp_port = mkOption {
      description = "opensearch port for the node to node communication.";
      default = 9300;
      type = types.int;
    };

    cluster_name = mkOption {
      description = "opensearch name that identifies your cluster for auto-discovery.";
      default = "opensearch";
      type = types.str;
    };

    single_node = mkOption {
      description = "Start a single-node cluster";
      default = true;
      type = types.bool;
    };

    extraConf = mkOption {
      description = "Extra configuration for opensearch.";
      default = "";
      type = types.str;
      example = ''
        node.name: "opensearch"
        node.master: true
        node.data: false
      '';
    };

    logging = mkOption {
      description = "opensearch logging configuration.";
      default = ''
        logger.action.name = org.opensearch.action
        logger.action.level = info

        appender.console.type = Console
        appender.console.name = console
        appender.console.layout.type = PatternLayout
        appender.console.layout.pattern = [%d{ISO8601}][%-5p][%-25c{1.}] %marker%m%n

        rootLogger.level = info
        rootLogger.appenderRef.console.ref = console
      '';
      type = types.str;
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/opensearch";
      description = ''
        Data directory for opensearch.
      '';
    };

    extraCmdLineOptions = mkOption {
      description = "Extra command line options for the opensearch launcher.";
      default = [ ];
      type = types.listOf types.str;
    };

    extraJavaOptions = mkOption {
      description = "Extra command line options for Java.";
      default = [ ];
      type = types.listOf types.str;
      example = [ "-Djava.net.preferIPv4Stack=true" ];
    };

  };

  ###### implementation

  config = mkIf cfg.enable {
    systemd.services.opensearch = {
      description = "opensearch Daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      path = [ pkgs.inetutils ];
      environment = {
        OPENSEARCH_HOME = cfg.dataDir;
        OPENSEARCH_JAVA_OPTS = toString cfg.extraJavaOptions;
        OPENSEARCH_PATH_CONF = configDir;
      };
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/opensearch ${toString cfg.extraCmdLineOptions}";
        User = "opensearch";
        PermissionsStartOnly = true;
        LimitNOFILE = "1024000";
      };
      preStart = ''
        ${optionalString (!config.boot.isContainer) ''
          # Only set vm.max_map_count if lower than Opensearch's required minimum
          # This avoids conflict if configured via boot.kernel.sysctl
          if [ `${pkgs.procps}/bin/sysctl -n vm.max_map_count` -lt 262144 ]; then
            ${pkgs.procps}/bin/sysctl -w vm.max_map_count=262144
          fi
        ''}

        mkdir -m 0700 -p ${cfg.dataDir}

        ln -sfT ${cfg.package}/lib ${cfg.dataDir}/lib
        ln -sfT ${cfg.package}/modules ${cfg.dataDir}/modules

        # opensearch needs to create the opensearch.keystore in the config directory
        # so this directory needs to be writable.
        mkdir -m 0700 -p ${configDir}

        # Note that we copy config files from the nix store instead of symbolically linking them
        # because otherwise Security will raise the following exception:
        # java.security.AccessControlException:
        # access denied ("java.io.FilePermission" "/var/lib/opensearch/config/opensearch.yml" "read")

        cp ${opensearchYml} ${configDir}/opensearch.yml
        # Make sure the logging configuration for old opensearch versions is removed:
        rm -f "${configDir}/logging.yml"
        cp ${loggingConfigFile} ${configDir}/${loggingConfigFilename}
        mkdir -p ${configDir}/scripts
        cp ${cfg.package}/config/jvm.options ${configDir}/jvm.options
        # redirect jvm logs to the data directory
        mkdir -m 0700 -p ${cfg.dataDir}/logs
        ${pkgs.sd}/bin/sd 'logs/gc.log' '${cfg.dataDir}/logs/gc.log' ${configDir}/jvm.options \

        if [ "$(id -u)" = 0 ]; then chown -R opensearch:opensearch ${cfg.dataDir}; fi
      '';
      postStart = ''
        # Make sure opensearch is up and running before dependents
        # are started
        while ! ${pkgs.curl}/bin/curl -sS -f http://${cfg.listenAddress}:${toString cfg.port} 2>/dev/null; do
          sleep 1
        done
      '';
    };

    environment.systemPackages = [ cfg.package ];

    users = {
      groups.opensearch.gid = config.ids.gids.opensearch;
      users.opensearch = {
        uid = config.ids.uids.opensearch;
        description = "opensearch daemon user";
        isSystemUser = true;
        home = cfg.dataDir;
        group = "opensearch";
        useDefaultShell = true;
      };
    };
  };
}
