{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.elasticsearch;
  cfg_service = config.services.elasticsearch;
  fclib = config.fclib;

  esVersion =
    if config.flyingcircus.roles.elasticsearch6.enable
    then "6"
    else if config.flyingcircus.roles.elasticsearch7.enable
    then "7"
    else null;

  package = versionConfiguration.${esVersion}.package;
  enabled = esVersion != null;

  versionConfiguration = {
    "6" = {
      package = pkgs.elasticsearch6-oss;
      serviceName = "elasticsearch6-node";
    };
    "7" = {
      package = pkgs.elasticsearch7-oss;
      serviceName = "elasticsearch7-node";
    };
    null = {
      package = null;
      serviceName = null;
    };
  };

  esNodes =
    if cfg.esNodes == null
    then map
      (service: head (lib.splitString "." service.address))
      (filter
        (s: s.service == versionConfiguration.${esVersion}.serviceName)
        config.flyingcircus.encServices)
    else cfg.esNodes;

  thisNode =
    if config.networking.domain != null
    then "${config.networking.hostName}.${config.networking.domain}"
    else "localhost";

  defaultClusterName = config.networking.hostName;

  clusterName =
    if cfg.clusterName == null
    then (fclib.configFromFile /etc/local/elasticsearch/clusterName defaultClusterName)
    else cfg.clusterName;

  additionalConfig =
    fclib.configFromFile /etc/local/elasticsearch/elasticsearch.yml "";

  currentMemory = fclib.currentMemory 1024;

  esHeap = fclib.min
    [ (currentMemory * cfg.heapPercentage / 100)
      (31 * 1024)];

  esShowConfig = pkgs.writeScriptBin "elasticsearch-show-config" ''
    cat /srv/elasticsearch/config/elasticsearch.yml
  '';

in
{

  options = with lib; {

    flyingcircus.roles.elasticsearch = {

      # This is a placeholder role, it does not support containers itself.
      supportsContainers = fclib.mkDisableContainerSupport;

      clusterName = mkOption {
        type = types.nullOr types.string;
        default = null;
        description = ''
          The clusterName elasticsearch will use.
        '';
      };

      dataDir = mkOption {
        type = types.path;
        default = "/srv/elasticsearch";
        description = ''
          Data directory for elasticsearch.
        '';
      };

      heapPercentage = mkOption {
        type = types.int;
        default = 50;
        description = ''
          Tweak amount of memory to use for ES heap
          (systemMemory * heapPercentage / 100)
        '';
      };

      esNodes = mkOption {
        type = types.nullOr (types.listOf types.string);
        default = null;
        description = ''
          Names of the nodes that join this cluster.
          By default, all ES nodes in a resource group are part of this cluster.
          ES7: Values must use the same format as nodeName (just the hostname by default)
          or cluster initialization will fail. All esNodes are possible initial masters.
        '';
      };

      nodeName = mkOption {
        type = types.nullOr types.string;
        default = config.networking.hostName;
        description = ''
          The name for this node. Defaults to the hostname.
        '';
      };
    };

    flyingcircus.roles.elasticsearch6 = {
      enable = mkEnableOption "Enable the Flying Circus elasticsearch6 role.";
      supportsContainers = fclib.mkEnableContainerSupport;
    };

    flyingcircus.roles.elasticsearch7 = {
      enable = mkEnableOption "Enable the Flying Circus elasticsearch7 role.";
      supportsContainers = fclib.mkEnableContainerSupport;
    };

    # Dummy option that does nothing on 21.05 to make upgrades to 21.11
    # easier.
    # Set it to false before upgrading multi-node clusters!
    # On 21.11, the option is required and has `true` as default which splits
    # multi-node clusters.
    # This behaviour breaks indices that have replicas and they cannot be
    # recovered.
    services.elasticsearch.single_node = mkOption {};

  };

  config = lib.mkMerge [

    (lib.mkIf enabled {

    environment.systemPackages = [
      esShowConfig
    ];

    services.elasticsearch = {
      enable = true;
      package = package;
      listenAddress = thisNode;
      dataDir = cfg.dataDir;
      cluster_name = clusterName;
      extraJavaOptions = [
        "-Des.path.scripts=${cfg_service.dataDir}/scripts"
        "-Des.security.manager.enabled=false"
        # Xms and Xmx are already defined as cmdline args by config/jvm.options.
        # Appending the next two lines overrides the former.
        "-Xms${toString esHeap}m"
        "-Xmx${toString esHeap}m"
        "-Dlog4j2.formatMsgNoLookups=true"
        # Use new ES7 style for the publish address to avoid the annoying warning in ES6/7.
        (lib.optionalString (esVersion == "6") "-Des.http.cname_in_publish_address=true")
        (lib.optionalString (esVersion == "7") "-Des.transport.cname_in_publish_address=true")
      ];

      extraConf = ''
        node.name: ${cfg.nodeName}
        discovery.zen.ping.unicast.hosts: ${toJSON esNodes}
        bootstrap.memory_lock: true
        ${additionalConfig}
      '' + (lib.optionalString (esVersion == "7") ''
        cluster.initial_master_nodes: ${toJSON esNodes}
      '');
    };

    systemd.services.elasticsearch = {
      startLimitIntervalSec = 480;
      startLimitBurst = 3;
      serviceConfig = {
        LimitMEMLOCK = "infinity";
        Restart = "always";
      };
      preStart = lib.mkAfter ''
        # redirect jvm logs to the data directory
        mkdir -m 0700 -p ${cfg_service.dataDir}/logs
        ${pkgs.sd}/bin/sd 'logs/gc.log' '${cfg_service.dataDir}/logs/gc.log' ${cfg_service.dataDir}/config/jvm.options
        # Install scripts
        mkdir -p ${cfg_service.dataDir}/scripts
      '';
      postStart = let
        url = "http://${thisNode}:9200/_cat/health";
        in ''
        # Wait until available for use
        for count in {0..120}; do
            ${pkgs.curl}/bin/curl -s ${url} && exit
            echo "Trying to connect to ${url} for ''${count}s"
            sleep 1
        done
        echo "No connection to ${url} for 120s, giving up"
        exit 1
      '';
    };

    flyingcircus.activationScripts.elasticsearch = ''
      install -d -o ${toString config.ids.uids.elasticsearch} -g service -m 02775 \
        /etc/local/elasticsearch/
    '';

    environment.etc."local/elasticsearch/README.txt".text = ''
      Elasticsearch is running on this VM.

      It is forming the cluster named ${clusterName}
      To change the cluster name, add a file named "clusterName" here, with the
      cluster name as its sole contents.

      To add additional configuration options, create a file "elasticsearch.yml"
      here. Its contents will be appended to the base configuration.
    '';

    flyingcircus.services.sensu-client.checks = {

      es_circuit_breakers = {
        notification = "ES: Circuit Breakers active";
        command = ''
          ${pkgs.sensu-plugins-elasticsearch}/bin/check-es-circuit-breakers.rb \
            -h ${thisNode}
        '';
        interval = 300;
      };

      es_cluster_health = {
        notification = "ES: Cluster Health";
        command = ''
        ${pkgs.sensu-plugins-elasticsearch}/bin/check-es-cluster-health.rb \
          -h ${thisNode}
        '';
      };

      es_file_descriptor = {
        notification = "ES: File descriptors in use";
        command = ''
          ${pkgs.sensu-plugins-elasticsearch}/bin/check-es-file-descriptors.rb \
            -h ${thisNode}
        '';
        interval = 300;
      };

      es_heap = {
        notification = "ES: Heap too full";
        command = ''
          ${pkgs.sensu-plugins-elasticsearch}/bin/check-es-heap.rb \
            -h ${thisNode} -w 80 -c 90 -P
        '';
        interval = 300;
      };

      es_node_status = {
        notification = "ES: Node status";
        command = ''
          ${pkgs.sensu-plugins-elasticsearch}/bin/check-es-node-status.rb \
            -h ${thisNode}
        '';
      };

      es_shard_allocation_status = {
        notification = "ES: Shard allocation status";
        command = ''
          ${pkgs.sensu-plugins-elasticsearch}/bin/check-es-shard-allocation-status.rb \
            -s ${thisNode}
        '';
        interval = 300;
      };

    };

    systemd.services.prometheus-elasticsearch-exporter = {
      description = "Prometheus exporter for elasticsearch metrics";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.prometheus-elasticsearch-exporter ];
      script = ''
        exec elasticsearch_exporter\
            --es.uri http://${thisNode}:9200 \
            --web.listen-address localhost:9108
      '';
      serviceConfig = {
        User = "nobody";
        Restart = "always";
        PrivateTmp = true;
        WorkingDirectory = /tmp;
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      };
    };

    flyingcircus.services.telegraf.inputs = {
      prometheus  = [{
        urls = [ "http://localhost:9108/metrics" ];
      }];
    };
  })

  ];
}
