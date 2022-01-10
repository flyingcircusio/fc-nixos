{ lib, ... }:
let
  modulesFromHere = [
    "services/misc/gitlab.nix"
    "services/monitoring/prometheus.nix"
    "services/monitoring/prometheus/default.nix"
    "services/networking/jicofo.nix"
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
    ./collectdproxy.nix
    ./consul.nix
    ./gitlab
    ./graylog
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
    ./percona.nix
    ./postgresql.nix
    ./prometheus.nix
    ./rabbitmq.nix
    ./raid
    ./redis.nix
    ./sensu/client.nix
    ./telegraf

    (mkRemovedOptionModule [ "flyingcircus" "services" "percona" "rootPassword" ] "Change the root password via MySQL and modify secret files")
  ];
}
