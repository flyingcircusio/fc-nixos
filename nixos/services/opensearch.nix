{ options, config, lib, pkgs, ... }:

with builtins;

let
  inherit (config) fclib;
  cfg = config.flyingcircus.services.opensearch;
  opts = options.flyingcircus.services.opensearch;
  cfgUpstream = config.services.opensearch;

  localConfigDir = "/etc/local/opensearch";

  thisNode =
    if config.networking.domain != null
    then "${config.networking.hostName}.${config.networking.domain}"
    else "localhost";

  currentMemory = fclib.currentMemory 1024;

  openSearchHeap = fclib.min
    [ (currentMemory * cfg.heapPercentage / 100)
      (31 * 1024)];

  usingDefaultDataDir = cfgUpstream.dataDir == "/var/lib/opensearch";
  usingDefaultUserAndGroup = cfgUpstream.user == "opensearch" && cfgUpstream.group == "opensearch";
in
{

  options = with lib; {

    flyingcircus.services.opensearch = {

      enable = mkEnableOption "Enable the Flying Circus OpenSearch service.";

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
        description = ''
          Names of the nodes that join this cluster and are eligible as masters.

          Note that all of them have to use the same cluster name which must be
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
          You can set this to `config.flyingcircus.services.opensearch.nodes` to include
          all nodes.
        '';
      };

      clusterName = mkOption {
        type = types.str;
        description = ''
          The cluster name OpenSearch will use.
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

  };

  config = lib.mkMerge [

    (lib.mkIf cfg.enable {

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "opensearch-show-config" ''
        ${pkgs.rich-cli}/bin/rich --pager /etc/current-config/opensearch.yml
      '')
      (pkgs.writeShellScriptBin "opensearch-readme" ''
        ${pkgs.rich-cli}/bin/rich --pager ${localConfigDir}/README.md
      '')
    ];

    services.opensearch = {
      enable = true;

      settings = {
        "bootstrap.memory_lock" = true;
        "cluster.name" = cfg.clusterName;
        "discovery.seed_hosts" = cfg.nodes;
        "discovery.type" = if lib.length cfg.nodes == 1 then "single-node" else "";
        "network.host" = thisNode;
        "node.name" = cfg.nodeName;
      } // lib.optionalAttrs (cfg.initialMasterNodes != []) {
        "cluster.initial_master_nodes" = cfg.initialMasterNodes;
      };

      extraJavaOptions = [
        "-Des.path.scripts=${cfgUpstream.dataDir}/scripts"
        # Xms and Xmx are already defined as cmdline args by config/jvm.options.
        # Appending the next two lines overrides the former.
        "-Xms${toString openSearchHeap}m"
        "-Xmx${toString openSearchHeap}m"
        "-Dopensearch.transport.cname_in_publish_address=true"
      ];
    };

    # Allow sudo-srv and service users to run commands as opensearch.
    # There are various opensearch utilities that have to be run as
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
        # These values match the OpenSearch defaults for watermark.low and .high.
        # See https://opensearch.org/docs/latest/api-reference/cluster-api/cluster-settings/
        # for an explanation of what they do.
        warning = 85;
        critical = 90;
      };
    };

    systemd.services.opensearch = {
      startLimitIntervalSec = 480;
      startLimitBurst = 3;
      serviceConfig = {
        DynamicUser = lib.mkOverride 90 false;
        LimitMEMLOCK = "infinity";
        ExecStartPre =
          let
            migrateDataDir = ''
              set -e
              echo "Running as $(id opensearch)."
              if ls -A /srv/elasticsearch/*; then
                echo "Old elasticsearch data dir /srv/elasticsearch is not empty."
                if ls -A /var/lib/opensearch/*; then
                  echo "Not migrating, new data dir /var/lib/opensearch already has content!"
                else
                  echo "Copying existing Elasticsearch data to /var/lib/opensearch (using lightweight reflinks)..."
                  cp -r --reflink=always /srv/elasticsearch/* /var/lib/opensearch/
                  echo "Done. Old data dir /srv/elasticsearch can be deleted when OpenSearch starts up properly and you don't want to go back."
                fi
              else echo "Nothing found in Elasticsearch data dir.".
              fi

              chown -R opensearch:opensearch ${cfgUpstream.dataDir}/
            '';
          in
            lib.mkBefore
              (lib.optionals (usingDefaultDataDir && usingDefaultUserAndGroup) [
              "+${pkgs.writeShellScript "opensearch-migrate-datadir" migrateDataDir}"
            ] ++ [
              "${pkgs.writeShellScript "opensearch-link-jdk" "ln -sfT ${pkgs.jre_headless} ${cfgUpstream.dataDir}/jdk"}"
            ]);
      };
    };

    environment.variables = {
      OPENSEARCH_HOME = cfgUpstream.dataDir;
    };

    environment.etc."current-config/opensearch.yml".source = cfgUpstream.configFile;
    environment.etc."local/opensearch/README.md".text = let
      discoveryType = if cfgUpstream.settings."discovery.type" != "" then cfgUpstream.settings."discovery.type" else "multi-node";
    in
    ''
      # OpenSearch

      [OpenSearch](https://opensearch.org) version ${cfgUpstream.package.version} is running on this VM, with node
      name `${cfgUpstream.settings."node.name"}`. It is forming the cluster named
      `${cfgUpstream.settings."cluster.name"}` (${discoveryType}).

      The following nodes are eligible to be elected as master nodes:
      `${fclib.docList cfg.nodes}`

      ${lib.optionalString (cfg.initialMasterNodes != []) ''
      The node is running in multi-node bootstrap mode, `initialMasterNodes` is set to:
      `${fclib.docList cfg.initialMasterNodes}`

      WARNING: the `initialMasterNodes` setting should be removed after the cluster has formed!
      ''}

      ## Interaction

      The OpenSearch API is listening on the SRV interface. You can access
      the API of nodes in the same project via HTTP without authentication.
      Some examples:

      Show active nodes:

      ```
      curl ${thisNode}:9200/_cat/nodes
      ```

      Show cluster health:

      ```
      curl ${thisNode}:9200/_cat/health
      ```

      Show indices:

      ```
      curl ${thisNode}:9200/_cat/indices
      ```

      ### Running Configuration

      `/etc/current-config/opensearch.yml`:

      ```yaml
      ${readFile cfgUpstream.configFile}
      ```
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

    users = {
      groups.opensearch.gid = config.ids.gids.opensearch;
      users.opensearch = {
        uid = config.ids.uids.opensearch;
        description = "Opensearch daemon user";
        home = cfgUpstream.dataDir;
        group = "opensearch";
      };
    };
  })

  ];
}
