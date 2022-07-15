{ config, lib, ... }:
let
  # Map list of roles to a list of attribute sets enabling each role.
  # Turn the list of role names (["a", "b"]) into an attribute set
  # ala { <role> = { enable = true;}; }
  roleSet = lib.listToAttrs (
    map (role: { name = role; value = { enable = true; }; })
      config.flyingcircus.active-roles);
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
    ./kibana.nix
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
    ./statshost
    ./webdata_blackbee.nix
    ./webgateway.nix
    ./webproxy.nix

    (mkRemovedOptionModule [ "flyingcircus" "roles" "mysql" "rootPassword" ] "Change the root password via MySQL and modify secret files")
    (mkRenamedOptionModule [ "flyingcircus" "roles" "elasticsearch" "dataDir" ] [ "services" "elasticsearch" "dataDir" ])
    (mkRenamedOptionModule [ "flyingcircus" "roles" "rabbitmq38" ] [ "flyingcircus" "roles" "rabbitmq" ])
    (mkRenamedOptionModule [ "flyingcircus" "roles" "redis4" ] [ "flyingcircus" "roles" "redis" ])
    (mkRenamedOptionModule [ "flyingcircus" "roles" "statshost" "enable" ] [ "flyingcircus" "roles" "statshost-global" "enable" ])
    (mkRenamedOptionModule [ "flyingcircus" "roles" "statshost" "globalAllowedMetrics" ] [ "flyingcircus" "roles" "statshost-global" "allowedMetricPrefixes" ])
    (mkRenamedOptionModule [ "flyingcircus" "roles" "statshostproxy" ] [ "flyingcircus" "roles" "statshost-location-proxy" ])
    (mkRenamedOptionModule [ "flyingcircus" "roles" "kibana" "enable" ] [ "flyingcircus" "roles" "kibana6" "enable" ])
  ];

  options = {
    flyingcircus.roles.generic = {
      enable = lib.mkEnableOption "Generic role, which does nothing";
      supportsContainers = fclib.mkEnableContainerSupport;
    };
  };

  config = {
    flyingcircus.roles = roleSet;
  };

}
