{ config, lib, pkgs, ... }: with lib;

with builtins;

let
  cfg = config.flyingcircus.roles.memcached;
  fclib = config.fclib;

  defaultConfig = ''
    {
      "port": 11211,
      "maxMemory": 64,
      "maxConnections": 1024
    }
  '';

  localConfig =
    fclib.jsonFromFile "/etc/local/memcached/memcached.json" defaultConfig;

  port = localConfig.port;

in
{
  options = {
    flyingcircus.roles.memcached = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable the Flying Circus memcached role.";
      };

      supportsContainers = fclib.mkEnableDevhostSupport;

      listenAddresses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = fclib.network.lo.dualstack.addresses ++
                  fclib.network.srv.dualstack.addresses;
        defaultText = "the addresses of the networks `lo` and `srv` (IPv4 & IPv6)";
      };

    };
  };

  config = mkMerge [

  (mkIf cfg.enable {

    flyingcircus.localConfigDirs.memcached = {
      dir = "/etc/local/memcached";
      user = "memcached";
    };

    environment.etc = {
      "local/memcached/README.txt".text = ''
        Put your local memcached configuration as JSON into `memcached.json`.

        Example:
        ${defaultConfig}
      '';
      "local/memcached/memcached.json.example".text = defaultConfig;
    };

    services.memcached = {
      enable = true;
      listen = concatStringsSep "," cfg.listenAddresses;
    } // localConfig;

    flyingcircus.services = {
      sensu-client.checks.memcached =
      let
        host =
          if localConfig ? listen
          then elemAt (lib.splitString "," localConfig.listen) 0
          else "localhost";
      in {
        notification = "memcached alive";
        command = ''
          ${pkgs.sensu-plugins-memcached}/bin/check-memcached-stats.rb \
          -h ${host} -p ${toString port}
        '';
      };

      telegraf.inputs.memcached = [
        {
          servers = [
            "localhost:${toString port}"
          ];
        }
      ];
    };

    # We want a fixed uid that is compatible with older releases.
    # Upstream doesn't set the uid.
    users.users.memcached.uid = config.ids.uids.memcached;
  })

  {
    flyingcircus.roles.statshost.prometheusMetricRelabel = [
      {
        source_labels = [ "__name__" ];
        regex = "(memcached)_(.+)_hits";
        replacement = "\${2}";
        target_label = "command";
      }
      {
        source_labels = [ "__name__" ];
        regex = "(memcached)_(.+)_hits";
        replacement = "hit";
        target_label = "status";
      }
      {
        source_labels = [ "__name__" ];
        regex = "(memcached)_(.+)_hits";
        replacement = "memcached_commands_total";
        target_label = "__name__";
      }
      {
        source_labels = [ "__name__" ];
        regex = "(memcached)_(.+)_misses";
        replacement = "\${2}";
        target_label = "command";
      }
      {
        source_labels = [ "__name__" ];
        regex = "(memcached)_(.+)_misses";
        replacement = "miss";
        target_label = "status";
      }
      {
        source_labels = [ "__name__" ];
        regex = "(memcached)_(.+)_misses";
        replacement = "memcached_commands_total";
        target_label = "__name__";
      }
    ];
  }
  ];
}
