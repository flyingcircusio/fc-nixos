{ config, lib, ... }:

with builtins;

let
  fclib = config.fclib;
in {
  imports = with lib; [
    ./antivirus.nix
    ./backyserver.nix
    ./coturn.nix
    ./docker.nix
    ./ceph/mon.nix
    ./ceph/osd.nix
    ./ceph/rgw.nix
    ./devhost
    ./external_net
    ./elasticsearch.nix
    ./gitlab.nix
    ./graylog.nix
    ./jitsi
    ./k3s
    ./lamp.nix
    ./loghost
    ./mailout.nix
    ./mailserver.nix
    ./memcached.nix
    ./mongodb.nix
    ./mysql.nix
    ./nfs.nix
    ./nginx.nix
    ./postgresql.nix
    ./rabbitmq.nix
    ./redis.nix
    ./servicecheck.nix
    ./slurm
    ./statshost
    ./webdata_blackbee.nix
    ./webgateway.nix
    ./webproxy.nix

    (mkRemovedOptionModule [ "flyingcircus" "roles" "mysql" "rootPassword" ] "Change the root password via MySQL and modify secret files")
    (mkRenamedOptionModule [ "flyingcircus" "roles" "elasticsearch" "dataDir" ] [ "services" "elasticsearch" "dataDir" ])
    (mkRenamedOptionModule [ "flyingcircus" "roles" "statshost" "enable" ] [ "flyingcircus" "roles" "statshost-global" "enable" ])
    (mkRenamedOptionModule [ "flyingcircus" "roles" "statshost" "globalAllowedMetrics" ] [ "flyingcircus" "roles" "statshost-global" "allowedMetricPrefixes" ])
    (mkRenamedOptionModule [ "flyingcircus" "roles" "statshostproxy" ] [ "flyingcircus" "roles" "statshost-location-proxy" ])
  ];

  options = {
    flyingcircus.roles.generic = {
      enable = lib.mkEnableOption "Generic role, which does nothing";
      supportsContainers = fclib.mkEnableContainerSupport;
    };
  };

  config = {
    # Map list of roles to a list of attribute sets enabling each role.
    # Turn the list of role names (["a", "b"]) into an attribute set
    # ala { <role> = { enable = true;}; }
    # Roles are ignored if the initial run marker of fc-agent is still present
    # to get the new system ready for SSH connections more quickly and reliably.
    flyingcircus.roles =
      (lib.optionalAttrs
        (!pathExists "/etc/nixos/fc_agent_initial_run")
        (lib.listToAttrs (
          map (role: { name = role; value = { enable = true; }; })
            config.flyingcircus.active-roles)));
  };

}
