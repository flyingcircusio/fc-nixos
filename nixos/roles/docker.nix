{ config, lib, pkgs, ... }:

let
  fclib = config.fclib;
  cfg = config.flyingcircus.roles.docker;
in
{
  options = {
    flyingcircus.roles.docker = {
      enable = lib.mkEnableOption "Enable Docker";
      supportsContainers = fclib.mkEnableDevhostSupport;
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable) {
      environment.systemPackages = [ pkgs.docker-compose ];
      flyingcircus.users.serviceUsers.extraGroups = [ "docker" ];
      virtualisation.docker.enable = true;

      networking.firewall.extraCommands = lib.mkOrder 1200 ''
        # FC docker rules (1200)
        # allow access to host from docker networks, we consider this identical
        # to access from locally running processes.
        # We grant the full RFC1918 172.16.0.0/12 range.
        iptables -w -A nixos-fw -i br-+ -s 172.16.0.0/12 -j nixos-fw-accept
        iptables -w -A nixos-fw -i docker+ -s 172.16.0.0/12 -j nixos-fw-accept

        ip46tables -N fc-docker 2>/dev/null || true
        ip46tables -A fc-docker -m conntrack --ctstate RELATED,ESTABLISHED -j nixos-fw-accept
        ip46tables -A fc-docker -i ${fclib.network.srv.interface} -j fc-resource-group
        ip46tables -A fc-docker -i ${fclib.network.srv.interface} -j nixos-fw-refuse
        ip46tables -A fc-docker -i ${fclib.network.fe.interface} -j nixos-fw-refuse

        ip46tables -N DOCKER-USER 2>/dev/null || true
        ip46tables -I DOCKER-USER 1 ! -i docker+ -o docker+ -j fc-docker
        # End FC docker rules (1200)
      '';

      networking.firewall.extraStopCommands = lib.mkOrder 1100 ''
        # FC docker rules (1100)
        iptables -w -D nixos-fw -i br-+ -s 172.16.0.0/12 -j nixos-fw-accept 2>/dev/null || true
        iptables -w -D nixos-fw -i docker+ -s 172.16.0.0/12 -j nixos-fw-accept 2>/dev/null || true
        ip46tables -D DOCKER-USER ! -i docker+ -o docker+ -j fc-docker 2>/dev/null || true
        ip46tables -F fc-docker 2>/dev/null || true
        ip46tables -X fc-docker 2>/dev/null || true
        # End FC docker rules (1100)
      '';
    })

    (lib.mkIf (!cfg.enable) {
      networking.firewall.extraStopCommands = lib.mkOrder 1100 ''
        # FC docker rules (1100) -- ensure absence of docker firewall configuration
        ip46tables -D DOCKER-USER ! -i docker+ -o docker+ -j fc-docker 2>/dev/null || true
        ip46tables -F fc-docker 2>/dev/null || true
        ip46tables -X fc-docker 2>/dev/null || true
        # End FC docker rules (1100)
      '';
    })

  ];
}
