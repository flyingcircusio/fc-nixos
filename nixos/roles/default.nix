{ config, lib, ... }:

with builtins;

let
  fclib = config.fclib;
in
{
  imports = with lib; [
    ./ai-api-gateway.nix
    ./ai-model-server.nix
    ./antivirus.nix
    ./backyserver.nix
    ./ceph/mon.nix
    ./ceph/osd.nix
    ./ceph/rgw.nix
    ./consul
    ./coturn.nix
    ./devhost
    ./docker.nix
    ./elasticsearch.nix
    ./external_net
    ./faro_frontend.nix
    ./ferretdb.nix
    ./gitlab.nix
    ./graylog.nix
    ./jitsi
    ./k3s
    ./kvm
    ./lamp.nix
    ./loghost.nix
    ./loki.nix
    ./loki-relay.nix
    ./mailout.nix
    ./mailserver.nix
    ./mariadb.nix
    ./matomo.nix
    ./memcached.nix
    ./mongodb.nix
    ./mysql.nix
    ./nfs.nix
    ./nginx.nix
    ./open-webui.nix
    ./opensearch.nix
    ./opensearch_dashboards.nix
    ./postgresql.nix
    ./rabbitmq.nix
    ./redis.nix
    ./rgw-location-proxy.nix
    ./router
    ./servicecheck.nix
    ./slurm
    ./statshost
    ./tempo.nix
    ./webdata_blackbee.nix
    ./webgateway.nix
    ./webproxy.nix

    # Removed
    (mkRemovedOptionModule [
      "flyingcircus"
      "roles"
      "loghost-location"
      "enable"
    ] "Last platform version that supported graylog/loghost was 22.05.")
    (mkRemovedOptionModule [
      "flyingcircus"
      "roles"
      "mysql"
      "rootPassword"
    ] "Change the root password via MySQL and modify secret files.")
    (mkRemovedOptionModule [
      "flyingcircus"
      "roles"
      "statshostproxy"
      "enable"
    ] "Use flyingcircus.roles.statshost-location-proxy.enable instead.")

    # Renamed
    (mkRenamedOptionModule
      [ "flyingcircus" "roles" "statshost" "enable" ]
      [ "flyingcircus" "roles" "statshost-global" "enable" ]
    )
    (mkRenamedOptionModule
      [ "flyingcircus" "roles" "statshost" "globalAllowedMetrics" ]
      [ "flyingcircus" "roles" "statshost-global" "allowedMetricPrefixes" ]
    )
  ];

  options = {
    flyingcircus.roles.generic = {
      enable = lib.mkEnableOption "Generic role, which does nothing";
      supportsContainers = fclib.mkEnableDevhostSupport;
    };
  };

  config = {
    # Map list of roles to a list of attribute sets enabling each role.
    # Turn the list of role names (["a", "b"]) into an attribute set
    # ala { <role> = { enable = true;}; }
    # Roles are ignored if the initial run marker of fc-agent is still present
    # to get the new system ready for SSH connections more quickly and reliably.
    flyingcircus.roles = (
      lib.optionalAttrs (!pathExists "/etc/nixos/fc_agent_initial_run") (
        lib.listToAttrs (
          map (role: {
            name = role;
            value = {
              enable = true;
            };
          }) config.flyingcircus.active-roles
        )
      )
    );
  };

}
