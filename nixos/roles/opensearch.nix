{ options, config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.opensearch;
  cfg_service = config.services.opensearch;
  inherit (config) fclib;

  localConfigDir = "/etc/local/opensearch";

  exampleConfig = ''
    { config, pkgs, lib, ...}:
    {
      flyingcircus.roles.opensearch = {
        # clusterName = "example";
        # nodes = [ "example00", "example02" ];
        # heapPercentage = 50;

        ## Only for initialization of new multi-node clusters!
        # initialMasterNodes = [ "example00" ];
      };
      services.opensearch.settings = {
        # "action.destructive_requires_name" = true;
      };
    }
  '';

  defaultNodes =
    map
      (service: head (lib.splitString "." service.address))
      (fclib.findServices "opensearch-node");
in
{

  options = with lib; {

    flyingcircus.roles.opensearch = {
      enable = mkEnableOption "Enable the Flying Circus OpenSearch role.";
      supportsContainers = fclib.mkEnableContainerSupport;

      clusterName = mkOption {
        type = types.str;
        default = config.networking.hostName;
        defaultText = "host name";
        description = ''
          The cluster name OpenSearch will use. By default, the host name is
          used. Because of this, you have to set the cluster name explicitly
          if you want to set up a multi-node cluster.
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

          If only one node is given here, the node will start in single-node
          mode which means that it won't try to find other OpenSearch nodes before
          initializing the cluster.

          Values must use the same format as nodeName (just the hostname
          by default) or cluster initialization will fail.
        '';
      };

      inherit (options.flyingcircus.services.opensearch) heapPercentage initialMasterNodes;
    };

  };

  config = lib.mkIf cfg.enable {

    environment.etc."local/opensearch/opensearch.nix.example".text =
      fclib.mkPlatform exampleConfig;

    environment.etc."local/opensearch/README.md".text = lib.mkAfter ''
      ## Role Configuration

      For more details, see the [opensearch role documentation](${fclib.roleDocUrl "opensearch"}).

      The role works without additional config for single-node setups.
      By default, the cluster name is the host name of the machine.

      Custom config can be set via NixOS options and is required for multi-node
      setups.

      Example:

      ```nix
      ${replaceStrings ["# "] [""] exampleConfig}
      ```

      See `${localConfigDir}/opensearch.nix.example`.

      Copy the content to `/etc/local/nixos/opensearch.nix` to include it in
      the system config.

      To activate config changes, run `sudo fc-manage switch`.

      Run `opensearch-show-config` as `service` or `sudo-srv` user to see
      the active configuration used by OpenSearch.


      ### Role NixOS Options

      ${fclib.docOption "flyingcircus.roles.opensearch.clusterName"}

      ${fclib.docOption "flyingcircus.roles.opensearch.nodes"}

      ${fclib.docOption "flyingcircus.roles.opensearch.initialMasterNodes"}

      ${fclib.docOption "flyingcircus.roles.opensearch.heapPercentage"}

      ### Upstream NixOS Options

      ${fclib.docOption "services.opensearch.settings"}
      Add arbitrary OpenSearch settings here. See
      [OpenSearch/opensearch.yml](https://github.com/opensearch-project/OpenSearch/blob/main/distribution/src/config/opensearch.yml)
      for an example config file.

      OpenSearch settings are specified as flat key value pairs like
      `"action.destructive_requires_name" = true`;

      Note that the key must be quoted to stop Nix from interpreting the name
      of the setting as a path to a nested attribute.
    '';

    flyingcircus.services.opensearch = {
      enable = true;
      inherit (cfg) clusterName heapPercentage initialMasterNodes nodes;
    };
  };
}
