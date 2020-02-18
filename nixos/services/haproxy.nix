{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.services.haproxy;
  fclib = config.fclib;

  haproxyCfg = pkgs.writeText "haproxy.conf" config.services.haproxy.config;

  configFiles = filter (p: lib.hasSuffix ".cfg" p) (fclib.files /etc/local/haproxy);

  haproxyCfgContent = concatStringsSep "\n" (map readFile configFiles);

  example = ''
    # haproxy configuration example - copy to haproxy.cfg and adapt.

    global
        daemon
        chroot /var/empty
        user haproxy
        group haproxy
        maxconn 4096
        log localhost local2
        stats socket ${cfg.statsSocket} mode 660 group nogroup level operator

    defaults
        mode http
        log global
        option httplog
        option dontlognull
        option http-server-close
        timeout connect 5s
        timeout client 30s    # should be equal to server timeout
        timeout server 30s    # should be equal to client timeout
        timeout queue 25s     # discard requests sitting too long in the queue

    listen http-in
        bind 127.0.0.1:8002
        bind ::1:8002
        default_backend be

    backend be
        server localhost localhost:8080
  '';

  daemon = "${pkgs.haproxy}/bin/haproxy";
  kill = "${pkgs.coreutils}/bin/kill";

in
{
  options.flyingcircus.services.haproxy = with lib; {

    enable = mkEnableOption "FC-customized HAproxy";

    haConfig = mkOption {
      type = types.lines;
      default = example;
      description = "Full HAProxy configuration.";
    };

    statsSocket = mkOption {
      type = types.string;
      default = "/run/haproxy_admin.sock";
    };

  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {

      environment.etc = {
        "local/haproxy/README.txt".text = ''
          HAProxy is enabled on this machine.

          Put your main haproxy configuration here as e.g. `haproxy.cfg`.
          There is also an example configuration here.

          If you need more than just one centralized configuration file,
          add more files named `*.cfg` here. They will get merged along
          in alphabetical order and used as `haproxy.cfg`.
        '';
        "local/haproxy/haproxy.cfg.example".text = example;

        "current-config/haproxy.cfg".source = haproxyCfg;
      };

      flyingcircus.services = {
        sensu-client.checks.haproxy_config = {
          notification = "HAProxy configuration check problems";
          command = "${daemon} -f /etc/current-config/haproxy.cfg -c || exit 2";
          interval = 300;
        };

        telegraf.inputs = {
          prometheus  = [ { urls = [ "http://localhost:9127/metrics" ]; } ];
        };
      };

      flyingcircus.syslog.separateFacilities = {
        local2 = "/var/log/haproxy.log";
      };

      services.haproxy.enable = true;
      services.haproxy.config =
        if configFiles == [] then example else haproxyCfgContent;

      systemd.services.haproxy = {
        reloadIfChanged = true;
      };

      flyingcircus.localConfigDirs.haproxy = {
        dir = "/etc/local/haproxy";
        user = "haproxy";
      };

      flyingcircus.services.sensu-client.checkEnvPackages = [
        pkgs.fc.check-haproxy
      ];

      systemd.services.prometheus-haproxy-exporter = {
        description = "Prometheus exporter for haproxy metrics";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        path = [ pkgs.haproxy ];
        script = ''
          exec ${pkgs.prometheus-haproxy-exporter}/bin/haproxy_exporter \
            --web.listen-address localhost:9127 \
            --haproxy.scrape-uri=unix:${cfg.statsSocket}
        '';
        serviceConfig = {
          User = "nobody";
          Restart = "always";
          PrivateTmp = true;
          WorkingDirectory = "/tmp";
          ExecReload = "${kill} -HUP $MAINPID";
        };
      };

    })

    {
      flyingcircus.roles.statshost.globalAllowedMetrics = [ "haproxy" ];
    }
  ];
}
