{ lib, ... }:
let
  modulesFromHere = [
    "services/misc/gitlab.nix"
    "services/monitoring/prometheus/default.nix"
    "services/monitoring/prometheus.nix"
    "services/networking/jitsi-videobridge.nix"
    "services/web-servers/nginx/default.nix"
  ];

in {
  disabledModules = modulesFromHere;

  imports = with lib; [
    ./collectdproxy.nix
    ./gitlab
    ./graylog.nix
    ./haproxy.nix
    ./jitsi/jitsi-videobridge.nix
    ./logrotate
    ./nginx
    ./nullmailer.nix
    ./percona.nix
    ./postgresql.nix
    ./prometheus.nix
    ./rabbitmq36.nix
    ./rabbitmq.nix
    ./redis.nix
    ./sensu/api.nix
    ./sensu/client.nix
    ./sensu/server.nix
    ./sensu/uchiwa.nix
    ./syslog.nix
    ./telegraf.nix

    (mkRemovedOptionModule [ "flyingcircus" "services" "percona" "rootPassword" ] "Change the root password via MySQL and modify secret files")
  ];
}
