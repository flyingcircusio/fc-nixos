{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.services.redis;
  fclib = config.fclib;

  generatedPassword =
    lib.removeSuffix "\n" (readFile
      (pkgs.runCommand "redis.password" {}
      "${pkgs.apg}/bin/apg -a 1 -M lnc -n 1 -m 32 > $out"));

  password = lib.removeSuffix "\n" (
    if cfg.password == null
    then (fclib.configFromFile /etc/local/redis/password generatedPassword)
    else cfg.password
  );

  extraConfig = fclib.configFromFile /etc/local/redis/custom.conf "";

in {
  options = with lib; {

    flyingcircus.services.redis = {
      enable = mkEnableOption "Preconfigured Redis";

      listenAddresses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        defaultText = "the addresses of the networks `lo` and `srv`";
        default = fclib.network.lo.dualstack.addresses ++
                  fclib.network.srv.dualstack.addresses;
      };

      password = mkOption {
        type = types.nullOr types.string;
        default = null;
        description = ''
          The password for redis. If null, a random password will be generated.
        '';
      };

      package = mkOption {
        type = types.package;
        default = pkgs.redis;
        description = "The precise Redis package to use";
        example = "pkgs.redis";
      };

      maxmemory = mkOption {
        type = types.str;
        default = "${toString ((fclib.currentMemory 1024) * cfg.memoryPercentage / 100)}mb";
        description = "Maximum memory redis is allowed to use for a dataset";
        example = "100mb";
      };

      maxmemory-policy = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          The exact behavior Redis follows when the maxmemory limit is reached is configured using the maxmemory-policy configuration directive.

          The following policies are available:

          - noeviction: return errors when the memory limit was reached and the client is trying to execute commands that could result in more memory to be used (most write commands, but DEL and a few more exceptions).
          - allkeys-lru: evict keys by trying to remove the less recently used (LRU) keys first, in order to make space for the new data added.
          - volatile-lru: evict keys by trying to remove the less recently used (LRU) keys first, but only among keys that have an expire set, in order to make space for the new data added.
          - allkeys-random: evict keys randomly in order to make space for the new data added.
          - volatile-random: evict keys randomly in order to make space for the new data added, but only evict keys with an expire set.
          - volatile-ttl: evict keys with an expire set, and try to evict keys with a shorter time to live (TTL) first, in order to make space for the new data added.

          Read more at https://redis.io/topics/lru-cache
        '';
        example = "noeviction";
      };

      memoryPercentage = mkOption {
        type = types.int;
        default = 80;
        description = "Amount of memory in percent to use as maximum for redis";
        example = "100";
      };
    };

  };

  config =
    lib.mkIf cfg.enable {

      assertions =
        [
          {
            assertion = extraConfig == "";
            message = ''
              Config via /etc/local/redis/custom.conf is not supported anymore.
              Please use a NixOS module with the option services.redis.servers."".settings instead
            '';
          }
        ];

      services.redis = {
        package = cfg.package;
        vmOverCommit = true;

        servers = {
          "" = {
            bind = concatStringsSep " " cfg.listenAddresses;
            enable = true;
            requirePass = password;
            settings = lib.mkMerge [
              (lib.mkIf (cfg.maxmemory-policy != null) {
                inherit (cfg) maxmemory-policy;
              })
              ({
                inherit (cfg) maxmemory;
              })
            ];
          };
        };
      };

      systemd.services.redis.serviceConfig.Restart = "always";

      flyingcircus.activationScripts.redis =
        lib.stringAfter [ "fc-local-config" ] ''
          if [[ ! -e /etc/local/redis/password ]]; then
            ( umask 007;
              echo ${lib.escapeShellArg password} > /etc/local/redis/password
              chown redis:service /etc/local/redis/password
            )
          fi
          chmod 0660 /etc/local/redis/password
        '';

      flyingcircus.localConfigDirs.redis = {
        dir = "/etc/local/redis";
        user = "redis";
      };

      flyingcircus.services = {
        sensu-client.checks.redis = {
          notification = "Redis alive";
          command = ''
            ${pkgs.sensu-plugins-redis}/bin/check-redis-ping.rb \
              -h localhost -P ${lib.escapeShellArg password}
          '';
        };

        telegraf.inputs.redis = [
          {
            servers = [
              "tcp://:${password}@localhost:${toString config.services.redis.servers."".port}"
            ];
            # Drop string fields. They are converted to labels in Prometheus
            # which blows up the number of metrics.
            fielddrop = [
              "aof_last_bgrewrite_status"
              "aof_last_write_status"
              "maxmemory_policy"
              "rdb_last_bgsave_status"
              "used_memory_dataset_perc"
              "used_memory_peak_perc"
            ];
          }
        ];
      };

      boot.kernel.sysctl = {
        "net.core.somaxconn" = 512;
      };

      environment.etc."local/redis/README.txt".text = ''
        Redis is running on this machine.

        You can find the password for the redis in the `password`. You can also change
        the redis password by changing the `password` file.

        Changing the config via custom.conf is not supported anymore. Please use a NixOS module
        with the option `services.redis.servers."".settings` instead.
      '';

      # We want a fixed uid that is compatible with older releases.
      # Upstream doesn't set the uid.
      users.users.redis.uid = config.ids.uids.redis;

    };
}
