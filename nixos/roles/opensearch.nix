{ options, config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.opensearch;
  opts = options.flyingcircus.roles.opensearch;
  cfg_service = config.services.opensearch;
  fclib = config.fclib;
  localConfigDir = "/etc/local/opensearch";

  optionDoc = name: let
    opt = opts."${name}";
  in
    lib.concatStringsSep "\n\n" [
      "**flyingcircus.roles.opensearch.${name}**"
      (lib.removePrefix "\n" (lib.removeSuffix "\n" opt.description))
    ];

  formatList = list:
    "[ ${lib.concatMapStringsSep " " (n: ''"${n}"'') list} ]";

  # XXX: We cannot get the config file path in the Nix store from Nix config.
  # so we have to use the location where the config is copied to when
  # OpenSearch is started. There, only the opensearch user can read the
  # config file which is annoying.
  # This should be changed in the upstream module to make it possible to find
  # the config file via a NixOS option and override it, if needed.
  configFile = "/srv/opensearch/config/opensearch.yml";

  openSearchServices = (fclib.findServices "opensearch-node");

  defaultNodes =
    map
      (service: head (lib.splitString "." service.address))
      openSearchServices;

  thisNode =
    if config.networking.domain != null
    then "${config.networking.hostName}.${config.networking.domain}"
    else "localhost";

  defaultClusterName = config.networking.hostName;

  currentMemory = fclib.currentMemory 1024;

  openSearchHeap = fclib.min
    [ (currentMemory * cfg.heapPercentage / 100)
      (31 * 1024)];

  openSearchShowConfig = pkgs.writeScriptBin "opensearch-show-config" ''
    sudo -u opensearch cat ${configFile}
  '';

in
{

  options = with lib; {

    flyingcircus.roles.opensearch = {

      enable = mkEnableOption "Enable the Flying Circus OpenSearch role.";

      # This is a placeholder role, it does not support containers itself.
      supportsContainers = fclib.mkDisableContainerSupport;
      clusterName = mkOption {
        type = types.str;
        default = defaultClusterName;
        defaultText = "Same as host name";
        description = ''
          The cluster name OpenSearch will use. The host name is used as default.
          Because of this, you have to set the cluster name explicitly if you
          want to set up a multi-node cluster.
        '';
      };

      heapPercentage = mkOption {
        type = types.int;
        default = 50;
        description = ''
          Percentage of memory to use for OpenSearch heap. Defaults to 50 % of
          available RAM: *systemMemory * heapPercentage / 100*
        '';
      };

      nodes = mkOption {
        type = types.listOf types.str;
        default = defaultNodes;
        defaultText = "all OpenSearch nodes in the resource group";
        description = ''
          Names of the nodes that join this cluster and are eligible as masters.
          By default, all OpenSearch nodes in a resource group are part of this cluster
          and master-eligible.
          Note that all of them have to use the same clusterName which must be
          set explicitly when you want to set up a multi-node cluster.

          If only one nodes is given here, the node will start in single-node
          mode which means that it won't try to find other OpenSearch nodes before
          initializing the cluster.

          Values must use the same format as nodeName (just the hostname
          by default) or cluster initialization will fail.
        '';
      };

      initialMasterNodes = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          Name of the nodes that should take a part in the initial master election.
          WARNING: This should only be set when initializing a cluster with multiple nodes
          from scratch and removed after the cluster has formed!
          By default, this is empty which means that the node will join an existing
          cluster or run in single-node mode when nodes has only one entry.
          You can set this to `config.flyingcircus.roles.opensearch.nodes` to include
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
          Additional YAML lines which are appended to the main `opensearch.yml` config file.
        '';
      };
    };

  };

  config = lib.mkMerge [

    (lib.mkIf cfg.enable {

    environment.systemPackages = [
      openSearchShowConfig
    ];

    services.opensearch = {
      enable = true;
      listenAddress = thisNode;
      dataDir = "/srv/opensearch";
      cluster_name = cfg.clusterName;
      extraJavaOptions = [
        "-Des.path.scripts=${cfg_service.dataDir}/scripts"
        # Xms and Xmx are already defined as cmdline args by config/jvm.options.
        # Appending the next two lines overrides the former.
        "-Xms${toString openSearchHeap}m"
        "-Xmx${toString openSearchHeap}m"
        "-Dopensearch.transport.cname_in_publish_address=true"
      ];

      single_node = lib.length cfg.nodes == 1;

      extraConf = ''
        node.name: ${cfg.nodeName}
        bootstrap.memory_lock: true
        discovery.seed_hosts: ${toJSON cfg.nodes}
      '' + (lib.optionalString (cfg.initialMasterNodes != []) ''
        cluster.initial_master_nodes: ${toJSON cfg.initialMasterNodes}
      '') + (lib.optionalString (cfg.extraConfig != "") ''
        # flyingcircus.roles.opensearch.extraConfig
      '' + cfg.extraConfig);
    };

    # Allow sudo-srv and service users to run commands as opensearch.
    # There are various opensearch utility tools that have to be run as
    # opensearch user.
    flyingcircus.passwordlessSudoRules = [
      {
        commands = [ "ALL" ];
        groups = [ "sudo-srv" "service" "opensearch" ];
        runAs = "opensearch";
      }
    ];

    flyingcircus.services.sensu-client = {
      expectedDiskCapacity = {
        # XXX look at opensearch docs for these values
        warning = 85;
        critical = 90;
      };
    };

    systemd.services.opensearch = {
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

    environment.etc."local/opensearch/opensearch.nix.example".text = ''
      { config, pkgs, lib, ...}:
      {
        flyingcircus.roles.opensearch = {
          # clusterName = "mycluster";
          # heapPercentage = 50;
          # Only for initialization of new multi-node clusters!
          # initialMasterNodes = config.flyingcircus.roles.opensearch.nodes;
          # extraConfig = '''
          # # some YAML
          # ''';
        };
      }
    '';

    environment.etc."local/opensearch/README.md".text = ''
      OpenSearch version (XXX) is running on this VM, with node
      name `${cfg.nodeName}`. It is forming the cluster named
      `${cfg.clusterName}` (${if cfg_service.single_node then "single-node" else "multi-node"}).

      The following nodes are eligible to be elected as master nodes:
      `${formatList cfg.nodes}`

      ${lib.optionalString (cfg.initialMasterNodes != []) ''
      The node is running in multi-node bootstrap mode, `initialMasterNodes` is set to:
      `${formatList cfg.initialMasterNodes}`

      WARNING: the `initialMasterNodes` setting should be removed after the cluster has formed!
      ''}

      ## Interaction

      The OpenSearch API is listening on the SRV interface. You can access
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
      setups. See `${localConfigDir}/opensearch/opensearch.nix.example`.
      Save the content to `/etc/local/nixos/opensearch.nix`, for example,
      to include it in the system config.

      To see the final rendered config for OpenSearch, use the
      `opensearch-show-config` command as service or sudo-srv user.

      To activate config changes, run `sudo fc-manage --build`.

      ### NixOS Options

      ${optionDoc "clusterName"}

      ${optionDoc "heapPercentage"}

      ${optionDoc "nodes"}

      ${optionDoc "initialMasterNodes"}

      ${optionDoc "extraConfig"}

    '';

    flyingcircus.services.sensu-client.checks = {

      opensearch_circuit_breakers = {
        notification = "OpenSearch: Circuit Breakers active";
        command = ''
          ${pkgs.sensu-plugins-elasticsearch}/bin/check-es-circuit-breakers.rb \
            -h ${thisNode}
        '';
        interval = 300;
      };

      opensearch_cluster_health = {
        notification = "OpenSearch: Cluster Health";
        command = ''
        ${pkgs.sensu-plugins-elasticsearch}/bin/check-es-cluster-health.rb \
          -h ${thisNode}
        '';
      };

      opensearch_heap = {
        notification = "OpenSearch: Heap too full";
        command = ''
          ${pkgs.sensu-plugins-elasticsearch}/bin/check-es-heap.rb \
            -h ${thisNode} -w 80 -c 90 -P
        '';
        interval = 300;
      };

      opensearch_node_status = {
        notification = "OpenSearch: Node status";
        command = ''
          ${pkgs.sensu-plugins-elasticsearch}/bin/check-es-node-status.rb \
            -h ${thisNode}
        '';
      };

      opensearch_shard_allocation_status = {
        notification = "OpenSearch: Shard allocation status";
        command = ''
          ${pkgs.sensu-plugins-elasticsearch}/bin/check-es-shard-allocation-status.rb \
            -s ${thisNode}
        '';
        interval = 300;
      };

    };

    systemd.services.prometheus-opensearch-exporter = {
      description = "Prometheus exporter for opensearch metrics";
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
