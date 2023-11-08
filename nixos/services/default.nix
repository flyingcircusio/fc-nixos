{ lib, ... }:
let
  modulesFromHere = [
    "services/monitoring/prometheus.nix"
    "services/monitoring/prometheus/default.nix"
    "services/networking/jicofo.nix"
    "services/networking/jibri/default.nix"
    "services/networking/jitsi-videobridge.nix"
    "services/networking/prosody.nix"
    "services/web-apps/jitsi-meet.nix"
    "services/web-apps/matomo.nix"
    "services/web-servers/nginx/default.nix"
  ];

in {
  disabledModules = modulesFromHere;

  imports = with lib; [
    ./ceph/client.nix
    ./ceph/server.nix
    ./consul.nix
    ./haproxy
    ./jitsi/jibri.nix
    ./jitsi/jicofo.nix
    ./jitsi/jitsi-meet.nix
    ./jitsi/jitsi-videobridge.nix
    ./jitsi/prosody.nix
    ./k3s/frontend.nix
    ./logrotate
    ./matomo.nix
    ./nginx
    ./nullmailer.nix
    ./opensearch.nix
    ./opensearch_dashboards.nix
    ./percona.nix
    ./postgresql
    ./prometheus.nix
    ./rabbitmq.nix
    ./raid
    ./redis.nix
    ./sensu/client.nix
    ./solr.nix
    ./telegraf
    ./varnish

    (mkRemovedOptionModule [ "flyingcircus" "services" "percona" "rootPassword" ] "Change the root password via MySQL and modify secret files")
  ];
}
