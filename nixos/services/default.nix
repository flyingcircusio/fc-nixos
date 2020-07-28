{ lib, ... }:
let
  modulesFromHere = [
    "services/misc/gitlab.nix"
    "services/monitoring/prometheus.nix"
    "services/monitoring/prometheus/default.nix"
    "services/web-servers/nginx/default.nix"
  ];

  modulesFromUnstable = [
    "misc/extra-arguments.nix"
    "services/continuous-integration/gitlab-runner.nix"
    "services/misc/docker-registry.nix"
    "services/monitoring/grafana.nix"
    "services/networking/prosody.nix"
    "services/search/elasticsearch.nix"
    "services/search/kibana.nix"
    "services/web-apps/jitsi-meet.nix"
  ];

  nixpkgs-unstable-src = (import ../../versions.nix {}).nixos-unstable;

in {
  disabledModules = modulesFromUnstable ++ modulesFromHere;

  imports = with lib; [
    ./box/client.nix
    ./collectdproxy.nix
    ./gitlab
    ./graylog.nix
    ./haproxy.nix
    ./jitsi/jicofo.nix
    ./jitsi/jitsi-videobridge.nix
    ./logrotate
    ./nginx
    ./percona.nix
    ./postgresql.nix
    ./prometheus.nix
    ./rabbitmq36.nix
    ./rabbitmq.nix
    ./redis.nix
    ./sensu.nix
    ./ssmtp.nix
    ./syslog.nix
    ./telegraf.nix

    (mkRemovedOptionModule [ "flyingcircus" "services" "percona" "rootPassword" ] "Change the root password via MySQL and modify secret files")
  ] ++ map (m: "${nixpkgs-unstable-src}/nixos/modules/${m}") modulesFromUnstable;
}
