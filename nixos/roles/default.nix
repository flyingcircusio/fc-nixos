{ config, lib, ... }:
let
  # Map list of roles to a list of attribute sets enabling each role.
  # Turn the list of role names (["a", "b"]) into an attribute set
  # ala { <role> = { enable = true;}; }
  roleSet = lib.listToAttrs (
    map (role: { name = role; value = { enable = true; }; })
      config.flyingcircus.active-roles);

in {
  imports = [
    ./docker.nix
    ./external_net
    ./antivirus.nix
    ./elasticsearch.nix
    ./graylog.nix
    ./kibana.nix
    ./loghost.nix
    ./mailserver.nix
    ./memcached.nix
    ./mongodb
    ./mysql.nix
    ./nfs.nix
    ./nginx.nix
    ./postgresql.nix
    ./rabbitmq.nix
    ./redis.nix
    ./statshost
    ./webdata_blackbee.nix
    ./webgateway.nix
    ./webproxy.nix
  ];

  flyingcircus.roles = roleSet;
}
