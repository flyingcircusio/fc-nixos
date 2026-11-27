{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.flyingcircus.roles.webproxy;
  fclib = config.fclib;

  cacheMemory = (fclib.currentAvailableMemory 256) / 100 * cfg.mallocMemoryPercentage;

  # Configuring Varnish/Vinyl follows multiple steps where the first non-null result will be used:
  # 1. structured config via the module system (see service definition)
  # 2. use the config from /etc/local/vinyl-cache/default.vcl
  # 3. use the contents NixOS configuration environments.etc."local/vinyl-cache/default.vcl"
  #    This is required in tests, as the file hasn't been written during evaluation
  # There is a fallback vinyl-cache -> varnish in paths for the migration path.
  # Also if the package is still varnish, /etc/local/varnish instead of /etc/local/vinyl-cached gets used.
  localVarnishCfg = fclib.configFromFile /etc/local/varnish/default.vcl null;
  varnishFallback = config.environment.etc."local/varnish/default.vcl".text or null;
  resolvedVarnish = if localVarnishCfg != null then localVarnishCfg else varnishFallback;

  localVinylCfg = fclib.configFromFile /etc/local/vinyl-cache/default.vcl null;
  vinylFallback = config.environment.etc."local/vinyl-cache/default.vcl".text or resolvedVarnish;
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
    warnings =
      lib.optionals (localVarnishCfg != null && localVinylCfg == null) [
        "Vinyl Cache is still configured using /etc/local/varnish/default.vcl. Please migrate this files' contents to /etc/local/vinyl-cache/default.vcl"
      ]
      ++ lib.optionals (localVarnishCfg != null && localVinylCfg != null) [
        "Conflicting configuration files detected. Inactive file /etc/local/varnish/default.vcl is superseded by /etc/local/vinyl-cache/default.vcl. Please remove the inactive file."
      ];
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
      "d /etc/local/varnish 2775 vinyl-cache service"
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
