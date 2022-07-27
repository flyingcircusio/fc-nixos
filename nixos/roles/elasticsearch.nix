{ options, config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.elasticsearch;
  opts = options.flyingcircus.roles.elasticsearch;
  cfg_service = config.services.elasticsearch;
  fclib = config.fclib;
  localConfigDir = "/etc/local/elasticsearch";

  optionDoc = name: let
    opt = opts."${name}";
  in
    lib.concatStringsSep "\n\n" [
      "**flyingcircus.roles.elasticsearch.${name}**"
      (lib.removePrefix "\n" (lib.removeSuffix "\n" opt.description))
    ];

  formatList = list:
    "[ ${lib.concatMapStringsSep " " (n: ''"${n}"'') list} ]";

  esVersion =
    if config.flyingcircus.roles.elasticsearch6.enable
    then "6"
    else if config.flyingcircus.roles.elasticsearch7.enable
    then "7"
    else null;

  package = versionConfiguration.${esVersion}.package;
  enabled = esVersion != null;

  # XXX: We cannot get the config file path in the Nix store from Nix config.
  # so we have to use the location where the config is copied to when
  # Elasticsearch is started. There, only the elasticsearch user can read the
  # config file which is annoying.
  # This should be changed in the upstream module to make it possible to find
  # the config file via a NixOS option and override it, if needed.
  configFile = "/srv/elasticsearch/config/elasticsearch.yml";

  versionConfiguration = {
    "6" = {
      package = pkgs.elasticsearch6-oss;
    };
    "7" = {
      package = pkgs.elasticsearch7-oss;
    };
    null = {
      package = null;
    };
  };

  esServices =
    (fclib.findServices "elasticsearch6-node") ++
    (fclib.findServices "elasticsearch7-node");

  defaultEsNodes =
    map
      (service: head (lib.splitString "." service.address))
      esServices;

  masterQuorum = (length cfg.esNodes) / 2 + 1;

  thisNode =
    if config.networking.domain != null
    then "${config.networking.hostName}.${config.networking.domain}"
    else "localhost";

  defaultClusterName = config.networking.hostName;

  configFromLocalConfigDir =
    fclib.configFromFile "${localConfigDir}/elasticsearch.yml" "";

  currentMemory = fclib.currentMemory 1024;

  esHeap = fclib.min
    [ (currentMemory * cfg.heapPercentage / 100)
      (31 * 1024)];

  esShowConfig = pkgs.writeScriptBin "elasticsearch-show-config" ''
    sudo -u elasticsearch cat ${configFile}
  '';

in
{

  options = with lib; {

    flyingcircus.roles.elasticsearch = {

      # This is a placeholder role, it does not support containers itself.
      supportsContainers = fclib.mkDisableContainerSupport;

      clusterName = mkOption {
        type = types.str;
        default = fclib.configFromFile "${localConfigDir}/clusterName" defaultClusterName;
        defaultText = "value from ${localConfigDir}/clusterName or host name";
        description = ''
          The cluster name ES will use. By default, the string from
          `${localConfigDir}/clusterName is used. If the file doesn't
          exist, the host name is used as fallback. Because of this, you
          have to set the cluster name explicitly if you want to set up a
          multi-node cluster.
        '';
      };

      heapPercentage = mkOption {
        type = types.int;
        default = 50;
        description = ''
          Percentage of memory to use for ES heap. Defaults to 50 % of
          available RAM: *systemMemory * heapPercentage / 100*
        '';
      };

      esNodes = mkOption {
        type = types.listOf types.str;
        default = defaultEsNodes;
        defaultText = "all ES nodes in the resource group";
        description = ''
          Names of the nodes that join this cluster and are eligible as masters.
          By default, all ES nodes in a resource group are part of this cluster
          and master-eligible.
          Note that all of them have to use the same clusterName which must be
          set explicitly when you want to set up a multi-node cluster.

          If only one esNode is given here, the node will start in single-node
          mode which means that it won't try to find other ES nodes before
          initializing the cluster.

          Having both ES6 and ES7 nodes in a cluster is possible. This allows
          rolling upgrades. Note that new nodes that are added to a cluster
          have to use the newest version.

          ES7: Values must use the same format as nodeName (just the hostname
          by default) or cluster initialization will fail.
        '';
      };

      initialMasterNodes = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          *(ES7 only, has no effect for ES6)*

          Name of the nodes that should take a part in the initial master election.
          WARNING: This should only be set when initializing a cluster with multiple nodes
          from scratch and removed after the cluster has formed!
          By default, this is empty which means that the node will join an existing
          cluster or run in single-node mode when esNodes has only one entry.
          You can set this to `config.flyingcircus.roles.elasticsearch.esNodes` to include
          all automatically discovered nodes.
        '';
      };

      nodeName = mkOption {
        type = types.nullOr types.string;
        default = config.networking.hostName;
        description = ''
          The name for this node. Defaults to the hostname.
        '';
      };
      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Additional YAML lines which are appended to the main `elasticsearch.yml` config file.
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
  };

  config = lib.mkMerge [

    (lib.mkIf enabled {

    environment.systemPackages = [
      esShowConfig
    ];

    flyingcircus.roles.elasticsearch.extraConfig = configFromLocalConfigDir;

    services.elasticsearch = {
      enable = true;
      package = package;
      listenAddress = thisNode;
      dataDir = "/srv/elasticsearch";
      cluster_name = cfg.clusterName;
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

      single_node = lib.length cfg.esNodes == 1;

      extraConf = ''
        node.name: ${cfg.nodeName}
        bootstrap.memory_lock: true
      '' + (lib.optionalString (lib.versionOlder esVersion "7") ''
        discovery.zen.minimum_master_nodes: ${toString masterQuorum}
        discovery.zen.ping.unicast.hosts: ${toJSON cfg.esNodes}
      '') + (lib.optionalString (lib.versionAtLeast esVersion "7") ''
        discovery.seed_hosts: ${toJSON cfg.esNodes}
      '') + (lib.optionalString (lib.versionAtLeast esVersion "7" && cfg.initialMasterNodes != []) ''
        cluster.initial_master_nodes: ${toJSON cfg.initialMasterNodes}
      '') + (lib.optionalString (cfg.extraConfig != "") ''
        # flyingcircus.roles.elasticsearch.extraConfig
      '' + cfg.extraConfig);
    };

    # Allow sudo-srv and service users to run commands as elasticsearch.
    # There are various elasticsearch utility tools that have to be run as
    # elasticsearch user.
    flyingcircus.passwordlessSudoRules = [
      {
        commands = [ "ALL" ];
        groups = [ "sudo-srv" "service" "elasticsearch" ];
        runAs = "elasticsearch";
      }
    ];

    flyingcircus.services.sensu-client = {
      expectedDiskCapacity = {
        # same as https://www.elastic.co/guide/en/elasticsearch/reference/7.17/modules-cluster.html#disk-based-shard-allocation
        warning = 85;
        critical = 90;
      };
    };

    systemd.services.elasticsearch = {
      startLimitIntervalSec = 480;
      startLimitBurst = 3;
      serviceConfig = {
        LimitMEMLOCK = "infinity";
        Restart = "always";
      };
      preStart = lib.mkAfter ''
        # Install scripts
        mkdir -p ${cfg_service.dataDir}/scripts
      '';
    };

    flyingcircus.activationScripts.elasticsearch = ''
      install -d -o ${toString config.ids.uids.elasticsearch} -g service -m 02775 \
        ${localConfigDir}
    '';

    environment.etc."local/elasticsearch/elasticsearch.nix.example".text = ''
      { config, pkgs, lib, ...}:
      {
        flyingcircus.roles.elasticsearch = {
          # clusterName = "mycluster";
          # heapPercentage = 50;
          # Only for initialization of new multi-node clusters!
          # initialMasterNodes = config.flyingcircus.roles.elasticsearch.esNodes;
          # extraConfig = '''
          # # some YAML
          # ''';
        };
      }
    '';

    environment.etc."local/elasticsearch/README.md".text = ''
      Elasticsearch version ${esVersion}.x is running on this VM, with node
      name `${cfg.nodeName}`. It is forming the cluster named
      `${cfg.clusterName}` (${if cfg_service.single_node then "single-node" else "multi-node"}).

      The following nodes are eligible to be elected as master nodes:
      `${formatList cfg.esNodes}`

      ${lib.optionalString (cfg.initialMasterNodes != []) ''
      The node is running in multi-node bootstrap mode, `initialMasterNodes` is set to:
      `${formatList cfg.initialMasterNodes}`

      WARNING: the `initialMasterNodes` setting should be removed after the cluster has formed!
      ''}

      ## Interaction

      The Elasticsearch API is listening on the SRV interface. You can access
      the API of nodes in the same project via HTTP without authentication.
      Some examples:

      Show active nodes:

      ```
      curl ${config.networking.hostName}:9200/_cat/nodes
      ```

      Show cluster health:

      ```
      curl ${config.networking.hostName}:9200/_cat/health
      ```

      Show indices:

      ```
      curl ${config.networking.hostName}:9200/_cat/indices
      ```

      ## Configuration

      The role works without additional config for single-node setups.
      By default, the cluster name is the host name of the machine.

      Custom config can be set via NixOS options and is required for multi-node
      setups. Plain config in `${localConfigDir}` is still supported, too.
      See `${localConfigDir}/elasticsearch/elasticsearch.nix.example` for an example.
      Save the content to `/etc/local/nixos/elasticsearch.nix`, for example, to
      include it in the system config.

      To see the final rendered config for Elasticsearch, use the
      `elasticsearch-show-config` command as service or sudo-srv user.

      To activate config changes, run `sudo fc-manage --build`.

      ### NixOS Options

      ${optionDoc "clusterName"}

      ${optionDoc "heapPercentage"}

      ${optionDoc "esNodes"}

      ${optionDoc "initialMasterNodes"}

      ${optionDoc "extraConfig"}

      ## Legacy Custom Config

      You can add a file named `${localConfigDir}/clusterName`, with the
      cluster name as its sole contents.

      To add additional configuration options, create a file
      `${localConfigDir}/elasticsearch.yml`. Its contents will be appended to
      the base configuration.
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
