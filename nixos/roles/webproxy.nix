{ config, lib, pkgs, ... }:

let
  cfg = config.services.varnish;
  fccfg = config.flyingcircus.roles.webproxy;
  fclib = config.fclib;

  cacheMemory = (fclib.currentMemory 256) / 100 * fccfg.mallocMemoryPercentage;

  kill = "${pkgs.coreutils}/bin/kill";

  # if there is a default.vcl file, use that instead of the NixOS Varnish configuration
  rawVarnishCfg = fclib.configFromFile /etc/local/varnish/default.vcl null;
  # this is required for testing since the default.vcl file does not exist at build time
  varnishCfg = if rawVarnishCfg == null && config.environment.etc ? "local/varnish/default.vcl" then config.environment.etc."local/varnish/default.vcl".text else rawVarnishCfg;
in
{
  options = with lib; {
    flyingcircus.roles.webproxy = {
      enable = mkEnableOption "Flying Circus Varnish server role";
      supportsContainers = fclib.mkEnableContainerSupport;

      mallocMemoryPercentage = mkOption {
        type = types.int;
        default = 50;
        description = "Percentage of system memory to allocate to malloc cache";
      };

      listenAddresses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        defaultText = "the addresses of the networks `lo` and `srv` (IPv4 & IPv6)";
        default = fclib.network.srv.dualstack.addressesQuoted ++
                  fclib.network.lo.dualstack.addressesQuoted;
      };

    };
  };

  config = lib.mkMerge [
    (lib.mkIf fccfg.enable {
      warnings = lib.optional (varnishCfg != null) "Configuring varnish via /etc/local/varnish/default.vcl is deprecated, please migrate your Configuration to Nix";

      assertions = [{
        assertion = builtins.length (builtins.attrNames config.flyingcircus.services.varnish.virtualHosts) <= 1 || builtins.isNull varnishCfg;
        message  = ''
          Please remove the file `/etc/local/varnish/default.vcl` if you want to specify your Varnish configuration in Nix code.
        '';
      }];

      environment.etc = {
        "local/varnish/README.txt".text = ''
          Varnish is enabled on this machine.

          Varnish is listening on: ${cfg.http_address}

          Configure varnish via Nix or put your configuration into `default.vcl` (deprecated, please transition to a Nix config).
        '';
      };

      flyingcircus.services.sensu-client.checks = {
        varnish_status = {
          notification = "varnishadm status reports errors";
          command = "${cfg.package}/bin/varnishadm status";
          timeout = 180;
        };
        varnish_http = let
          # remove the optional protocol option at the end
          address = builtins.elemAt (lib.splitString "," cfg.http_address) 0;
          ip-port = lib.splitString ":" address;
          # default (empty) host and "*" are equivalent to 0.0.0.0
          # so the check can be run on localhost
          host = let
            tmp = builtins.elemAt ip-port 0;
          in
            if builtins.stringLength tmp > 0 && tmp != "*"
            then tmp
            else "127.0.0.1";
          # default port is 80 and can be omitted
          port =
            if builtins.length ip-port == 2
            then builtins.elemAt ip-port 1
            else 80;
        in {
          notification = "varnish port ${port} HTTP response";
          command = "check_http -H ${host} -p ${port} -c 10 -w 3 -t 20 -e HTTP";
        };
      };

      flyingcircus.services.telegraf.inputs.varnish = [
        {
          binary = "${cfg.package}/bin/varnishstat";
          stats = [ "all" ];
        }
      ];

      flyingcircus.users.serviceUsers.extraGroups = [ "varnish" ];

      services.logrotate.settings = {
        "/var/log/varnish.log" = {
          create = "0644 varnish varnish";
          postrotate = "systemctl reload varnishncsa";
        };
      };

      flyingcircus.services.varnish = {
        enable = true;
        extraCommandLine = "-s malloc,${toString cacheMemory}M";
        http_address = lib.concatMapStringsSep " -a "
          (addr: "${addr}:8008") fccfg.listenAddresses;
        virtualHosts = lib.optionalAttrs (varnishCfg != null) {
          "default-vcl" = {
            condition = "true";
            config = varnishCfg;
          };
        };
      };

      systemd.services = {
        varnishncsa = rec {
          after = [ "varnish.service" ];
          requires = after;
          description = "Varnish logging daemon";
          wantedBy = [ "multi-user.target" ];
          # We want to reopen logs with HUP. Varnishncsa must run in daemon mode for that.
          serviceConfig = {
            Type = "forking";
            Restart = "always";
            RuntimeDirectory = "varnish";
            PIDFile = "/run/varnish/varnishncsa.pid";
            User = "varnish";
            Group = "varnish";
            ExecStart = "${cfg.package}/bin/varnishncsa -D -a -w /var/log/varnish.log -P /run/varnish/varnishncsa.pid";
            ExecReload = "${kill} -HUP $MAINPID";
          };
        };
      };

      systemd.tmpfiles.rules = [
        "d /etc/local/varnish 2775 varnish service"
        "f /var/log/varnish.log 644 varnish varnish"
        # Link the default dir expected by varnish tools to
        # the actual location of the state dir. This makes the commands
        # usable without specifying the -n option every time.
        "L /run/varnishd - - - - ${cfg.stateDir}"
      ];

      users.groups.varnish.members = [
        "sensuclient"
        "telegraf"
      ];
    })

    {
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
    }
  ];
}
