{
  config,
  lib,
  pkgs,
  ...
}:

with builtins;

let
  cfg = config.flyingcircus.services.redis;
  fclib = config.fclib;

  extraConfig = fclib.configFromFile /etc/local/redis/custom.conf "";

  enabledServers = lib.filterAttrs (_: getAttr "enable") config.services.redis.servers;

  redisServiceName = name: if name == "" then "redis" else "redis-${name}";

  # If Redis only has a Unix socket that doesn't have r/w access for its group,
  # then Telegraf and Sensu can't connect to it. This will give a warning.
  isGroupRW =
    mask:
    let
      groupPart = lib.mod (div mask 10) 10;
    in
    bitAnd groupPart 2 == 2 && bitAnd groupPart 4 == 4;

  serversByConnection = lib.groupBy (
    serverName:
    let
      cfg = enabledServers.${serverName};
    in
    if cfg.bind != null && cfg.port > 0 then
      "tcp"
    else if cfg.unixSocket != null && isGroupRW cfg.unixSocketPerm then
      "uds"
    else
      "none"
  ) (attrNames enabledServers);

  bind = bindAddrs: head (lib.splitString " " bindAddrs);

  mkSensuCheck =
    name: connArgs:
    let
      # If a Redis server requires password authentication (i.e. requirePass or requirePassFile
      # is not `null`), then pass the raw password or the contents of requirePassFile
      # to the `check-redis-ping` invocation.
      passwordExpr =
        if enabledServers.${name}.requirePass != null then
          enabledServers.${name}.requirePass
        else if enabledServers.${name}.requirePassFile != null then
          ''"$(<${enabledServers.${name}.requirePassFile})"''
        else
          null;
    in
    lib.nameValuePair (redisServiceName name) {
      notification = "Redis" + lib.optionalString (name != "") " (instance ${name})" + " alive";
      command = ''
        ${pkgs.sensu-plugins-redis}/bin/check-redis-ping.rb \
          ${lib.optionalString (passwordExpr != null) "-P ${passwordExpr}"} ${connArgs}
      '';
    };

  checks = lib.listToAttrs (
    lib.forEach (serversByConnection.tcp or [ ]) (
      name:
      mkSensuCheck name "-h ${bind enabledServers.${name}.bind} -p ${
        toString enabledServers.${name}.port
      }"
    )
    ++ lib.forEach (serversByConnection.uds or [ ]) (
      name: mkSensuCheck name "-s ${enabledServers.${name}.unixSocket}"
    )
  );

  # Drop string fields. They are converted to labels in Prometheus
  # which blows up the number of metrics.
  telegrafFielddrop = [
    "aof_last_bgrewrite_status"
    "aof_last_write_status"
    "maxmemory_policy"
    "rdb_last_bgsave_status"
    "used_memory_dataset_perc"
    "used_memory_peak_perc"
  ];

  telegrafInputs =
    let
      # If a Redis server requires password authentication (i.e. requirePass or requirePassFile
      # is not `null`), then the password must be passed to the telegraf config for gathering metrics.
      # If requirePass is used, we inject the raw password into the Redis URL inside the config.
      # If requirePassFile is used, we inject the password by substituting an environment
      # variable, i.e. we write `${REDIS_PASSWORD_name}` into the telegraf config
      # which gets replaced by the actual password when the service starts.
      mkPasswordExpr =
        name:
        if enabledServers.${name}.requirePass != null then
          enabledServers.${name}.requirePass
        else if enabledServers.${name}.requirePassFile != null then
          "\${REDIS_PASSWORD_${escape name}}"
        else
          null;
    in
    map (
      name:
      let
        passwordExpr = mkPasswordExpr name;
      in
      {
        servers = [
          "tcp://${lib.optionalString (passwordExpr != null) ":${passwordExpr}@"}${
            bind enabledServers.${name}.bind
          }:${toString enabledServers.${name}.port}"
        ];
        fielddrop = telegrafFielddrop;
      }
    ) (serversByConnection.tcp or [ ])
    ++ map (
      name:
      let
        passwordExpr = mkPasswordExpr name;
      in
      {
        servers = [
          "unix://${enabledServers.${name}.unixSocket}"
        ];
        fielddrop = telegrafFielddrop;
      }
      // lib.optionalAttrs (passwordExpr != null) {
        password = passwordExpr;
      }
    ) (serversByConnection.uds or [ ]);

  # Usually, the access to Redis sockets is restricted, e.g. to user & group.
  # To allow Telegraf and Sensu access to it, their processes need to be
  # in these groups as well (see `SupplementaryGroups` in `systemd.exec(5)`).
  supplementaryGroups = map (name: config.services.redis.servers.${name}.group) (
    serversByConnection.uds or [ ]
  );

  escape = builtins.replaceStrings [ "-" ] [ "__" ];

in
{
  options = with lib; {

    flyingcircus.services.redis = {
      enable = mkEnableOption "Preconfigured Redis";

      listenAddresses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        defaultText = "the addresses of the networks `lo` and `srv` (IPv4 & IPv6)";
        default = fclib.network.lo.dualstack.addresses ++ fclib.network.srv.dualstack.addresses;
      };

      password = mkOption {
        type = types.nullOr types.str;
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
        defaultText = "100mb";
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
        default = 80 / (length (attrNames enabledServers));
        defaultText = "80 / len(enabledServers)";
        description = "Amount of memory in percent to use as maximum for redis";
        example = "100";
      };
    };

  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optionals (serversByConnection ? none) [
      ''
        Cannot configure Telegraf metrics and Sensu checks for the following named redis servers:

        ${lib.concatMapStringsSep "\n" (name: "* ${name}") serversByConnection.none}

        This means that no TCP socket is configured for connection and the Unix socket either doesn't
        exist or cannot be accessed by its respective group.
      ''
    ];

    assertions = [
      {
        assertion = extraConfig == "";
        message = ''
          Config via /etc/local/redis/custom.conf is not supported anymore.
          Please use a NixOS module with the option services.redis.servers."".settings instead
        '';
      }
      {
        # This limitation is relevant for telegraf because we generate env
        # vars from the server names (and `__` is used to escape dashes).
        assertion = all (name: null != builtins.match "^[A-Za-z0-9_-]*$" name && !lib.hasInfix "__" name) (
          attrNames enabledServers
        );
        message = ''
          All Redis server names (keys of `services.redis.servers`) can only
          contain alphanumeric chars, `-` and `_`, but no consecutive underscores.
        '';
      }
      {
        assertion =
          config.services.redis.servers."".enable -> config.services.redis.servers."".requirePass == null;
        message = ''
          Setting a password for the default Redis server with requirePass
          is not supported. Please use `flyingcircus.services.redis.password`
          instead.
        '';
      }
      {
        # The default set by the platform is /etc/local/redis/password. If this is set
        # to something else, we read the password from that value.
        # The `null` case is undefined and thus rejected.
        assertion =
          config.services.redis.servers."".enable -> config.services.redis.servers."".requirePassFile != null;
        message = ''
          Value of `services.redis.servers."".requirePassFile`
          (currently `${toString config.services.redis.servers."".requirePassFile}`)
          must not be null.
        '';
      }
    ];

    # Ensure sensu client can talk to Redis via socket.
    systemd.services = lib.mkMerge [
      {
        sensu-client.serviceConfig.SupplementaryGroups = supplementaryGroups;
        telegraf.serviceConfig.SupplementaryGroups = supplementaryGroups;
      }
      (lib.mapAttrs' (
        name: _:
        lib.nameValuePair (redisServiceName name) {
          serviceConfig.Restart = "always";
        }
      ) enabledServers)
      {
        redis.before = [ "telegraf.service" ];
        redis.serviceConfig =
          let
            preStart = pkgs.writeShellScript "redis-prestart" (''
              (
                umask 077;
                ${
                  if cfg.password != null then
                    ''
                      echo ${lib.escapeShellArg cfg.password} > /etc/local/redis/password
                    ''
                  else if config.services.redis.servers."".requirePassFile != "/etc/local/redis/password" then
                    ''
                      cp ${config.services.redis.servers."".requirePassFile} /etc/local/redis/password
                    ''
                  else
                    ''
                      if [[ ! -e /etc/local/redis/password ]]; then
                        ${pkgs.apg}/bin/apg -a 1 -M lnc -n 1 -m 32 > /etc/local/redis/password
                      fi
                    ''
                }
              )
              chmod 0660 /etc/local/redis/password
              chown redis:service /etc/local/redis/password
            '');
          in
          {
            ExecStartPre = lib.mkBefore [
              ("+" + preStart)
            ];
            Restart = "always";
          };
      }
    ];

    services.redis = {
      package = cfg.package;
      vmOverCommit = true;

      servers = {
        "" = {
          bind = concatStringsSep " " cfg.listenAddresses;
          enable = lib.mkDefault true;
          requirePassFile = "/etc/local/redis/password";
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

    flyingcircus.localConfigDirs.redis = {
      dir = "/etc/local/redis";
      user = "redis";
    };

    flyingcircus.services = {
      sensu-client = { inherit checks; };

      telegraf.environmentVariablesFromFile = lib.concatMapAttrs (
        name:
        { requirePassFile, ... }:
        lib.optionalAttrs (requirePassFile != null) {
          "REDIS_PASSWORD_${escape name}" = requirePassFile;
        }
      ) enabledServers;

      telegraf.inputs.redis = telegrafInputs;
    };

    boot.kernel.sysctl = {
      "net.core.somaxconn" = 512;
    };

    environment.etc."local/redis/README.txt".text = ''
      Redis is running on this machine.

      You can find the password for the redis in the `password` file.
      You can also change the redis password by changing the `password` file.

      Changing the config via custom.conf is not supported anymore. Please use a NixOS module
      with the option `services.redis.servers."".settings` instead.
    '';

    # We want a fixed uid that is compatible with older releases.
    # Upstream doesn't set the uid.
    users.users.redis.uid = config.ids.uids.redis;

  };
}
