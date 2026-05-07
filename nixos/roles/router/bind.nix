{
  config,
  pkgs,
  lib,
  ...
}:

with builtins;

let
  inherit (config) fclib;
  inherit (config.flyingcircus) location;
  role = config.flyingcircus.roles.router;
  bindUser = config.systemd.services.bind.serviceConfig.User;
in
{
  options.flyingcircus.roles.router = with lib; {
    bindConfig = mkOption {
      type = types.str;
      description = "Configuration for named";
      default = if location == "standalone" then "" else null;
    };

    # TODO: remove after updating consumers
    bindStaticData = mkOption {
      type = types.attrsOf types.str;
      visible = false;
      default = { };
    };

    zoneGeneratorConfig = mkOption {
      type = types.str;
      description = "Configuration for the zone file generator";
      default = if location == "standalone" then "" else null;
    };
  };

  config = lib.mkIf role.enable {
    networking.resolvconf.useLocalResolver = false;

    environment.systemPackages = [
      # ensure that rndc is available in PATH
      pkgs.bind
    ];

    services.bind = {
      enable = true;
      directory = "/var/cache/named";
      configFile = pkgs.writeText "named.conf" role.bindConfig;
    };

    systemd.services.bind = {
      serviceConfig = {
        Restart = "always";
        ReadWritePaths = [
          "/var/log/bind/"
          "/etc/bind/"
        ];
      };
    };

    environment.etc = {
      "local/configure-zones.cfg".text = role.zoneGeneratorConfig;
    };

    systemd.tmpfiles.rules = [
      "d /var/log/bind 0755 ${bindUser} nogroup 180d"
      "z /etc/bind 0755 ${bindUser}"
    ];

    flyingcircus.services.sensu-client.checks.bind_resolver = {
      notification = "Bind can resolve hostnames";
      command = "check_dig -H localhost -l flyingcircus.io";
    };

    flyingcircus.agent.extraPreCommands = ''
      # Updates files in /etc/bind and /etc/bind/pri where also Nix-generated config exists.
      fc-zones
    '';

    networking.firewall.extraCommands = ''
      ip46tables -A nixos-fw -p tcp --dport 53 -j nixos-fw-accept
      ip46tables -A nixos-fw -p udp --dport 53 -j nixos-fw-accept
    '';
  };
}
