{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.flyingcircus.roles.webproxy;
  fclib = config.fclib;

  cacheMemory = (fclib.currentMemory 256) / 100 * cfg.mallocMemoryPercentage;

  localVinylCfg = fclib.configFromFile /etc/local/vinyl-cache/default.vcl null;
  vinylFallback = config.environment.etc."local/vinyl-cache/default.vcl".text or null;
  resolvedVinyl = if localVinylCfg != null then localVinylCfg else vinylFallback;

  fallbackCfg = resolvedVinyl;
in
{
  options = with lib; {
    flyingcircus.roles.webproxy = {
      enable = mkEnableOption "Flying Circus Vinyl Cache server role";
      supportsContainers = fclib.mkEnableDevhostSupport;

      package = mkPackageOption pkgs "vinyl-cache_9" { };

      mallocMemoryPercentage = mkOption {
        type = types.int;
        default = 50;
        description = "Percentage of system memory to allocate to malloc cache";
      };

      listenAddresses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        defaultText = "the addresses of the networks `lo` and `srv` (IPv4 & IPv6)";
        default = fclib.network.srv.dualstack.addressesQuoted ++ fclib.network.lo.dualstack.addressesQuoted;
      };

    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc = {
      "local/vinyl-cache/README.txt".text =
        let
          listen_str = lib.concatMapStringsSep ", " (
            listenCfg: "${listenCfg.proto} ${listenCfg.address}:${toString (listenCfg.port or "n/a")}"
          ) config.services.vinyl-cache.listen;
        in
        ''
          Vinyl Cache is enabled on this machine.

          Vinyl Cache is listening on: ${listen_str}

          Configure Vinyl Cache via Nix or put your configuration into `default.vcl`.
        '';
    };

    flyingcircus.services.sensu-client.checks = {
      vinyl_cache_status = {
        notification = "vinyladm status reports errors";
        command = "${cfg.package}/bin/vinyladm status";
        timeout = 180;
      };
      vinyl_cache_http =
        let
          check-vinyl-cache-http = pkgs.writers.writePython3BinFromFile ./check-vinyl-cache-http.py {
            dependencies = [
              cfg.package
              pkgs.monitoring-plugins
            ];
            flakeIgnore = [ "E501" ]; # ignore long lines
          };
        in
        {
          notification = "Vinyl Cache port 8008 HTTP response";
          command = lib.getExe check-vinyl-cache-http;
        };
    };

    flyingcircus.services.vinyl-cache = {
      enable = true;
      inherit (cfg) package;
      extraCommandLine = "-s malloc,${toString cacheMemory}M";
      listen = lib.map (addr: {
        address = addr;
        port = 8008;
      }) (lib.unique cfg.listenAddresses);
      fallbackConfig = lib.mkIf (fallbackCfg != null) fallbackCfg;
    };

    systemd.tmpfiles.rules = [
      "d /etc/local/vinyl-cache 2775 vinyl-cache service"
    ];

    flyingcircus.users.serviceUsers.extraGroups = [ "vinyl-cache" ];
    users.users.vinyl-cache = {
      group = "vinyl-cache";
      isSystemUser = true;
    };
    users.groups.vinyl-cache = {
      members = [
        "sensuclient"
        "telegraf"
      ];
    };

    # The telegraf varnish plugin is still compatible with vinyl cache 9
    flyingcircus.services.telegraf.inputs.varnish = [
      {
        binary = "${cfg.package}/bin/vinylstat";
        stats = [ "all" ];
      }
    ];
    flyingcircus.roles.statshost.prometheusMetricRelabel = [
      {
        source_labels = [ "__name__" ];
        regex = "(varnish_client_req|varnish_fetch)_(.+)";
        replacement = "\${2}";
        target_label = "status";
      }
      {
        source_labels = [ "__name__" ];
        regex = "(varnish_client_req|varnish_fetch)_(.+)";
        replacement = "\${1}";
        target_label = "__name__";
      }

      # Relabel
      {
        source_labels = [ "__name__" ];
        regex = "varnish_(\\w+)_(.+)__(\\d+)__(.+)";
        replacement = "\${1}";
        target_label = "backend";
      }
      {
        source_labels = [ "__name__" ];
        regex = "varnish_(\\w+)_(.+)__(\\d+)__(.+)";
        replacement = "varnish_\${4}";
        target_label = "__name__";
      }
    ];
  };
}
