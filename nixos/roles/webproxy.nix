{ config, lib, pkgs, ... }:

let
  cfg = config.services.varnish;
  fccfg = config.flyingcircus.roles.webproxy;
  fclib = config.fclib;

  vclExample = ''
    vcl 4.0;
    backend test {
      .host = "127.0.0.1";
      .port = "8080";
    }
  '';

  varnishCfg = fclib.configFromFile /etc/local/varnish/default.vcl vclExample;
  configFile = pkgs.writeText "default.vcl" varnishCfg;

  cacheMemory = (fclib.currentMemory 256) / 100 * fccfg.mallocMemoryPercentage;

  varnishCmd =
    "${cfg.package}/sbin/varnishd -a ${cfg.http_address}" +
    " -f /etc/current-config/varnish.vcl -n ${cfg.stateDir}" +
    " -s malloc,${toString cacheMemory}M" +
    lib.optionalString
      (cfg.extraCommandLine != "")
      " ${cfg.extraCommandLine}" +
    lib.optionalString
      (cfg.extraModules != [])
      " -p vmod_path='${lib.makeSearchPathOutput "lib" "lib/varnish/vmods" ([cfg.package] ++ cfg.extraModules)}' -r vmod_path" +
    " -F";

  kill = "${pkgs.coreutils}/bin/kill";
in
{

  options = with lib; {

    flyingcircus.roles.webproxy = {
      enable = mkEnableOption "Flying Circus varnish server role";
      supportsContainers = fclib.mkEnableContainerSupport;

      mallocMemoryPercentage = mkOption {
        type = types.int;
        default = 50;
        description = "Percentage of system memory to allocate to malloc cache";
      };

      listenAddresses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        defaultText = "the addresses of the networks `srv` and `lo`";
        default = fclib.network.srv.dualstack.addressesQuoted ++
                  fclib.network.lo.dualstack.addressesQuoted;
      };

    };
  };

  config = lib.mkMerge [
    (lib.mkIf fccfg.enable {

      environment.etc = {
        "local/varnish/README.txt".text = ''
          Varnish is enabled on this machine.

          Varnish is listening on: ${cfg.http_address}

          Put your configuration into `default.vcl`.
        '';
        "local/varnish/default.vcl.example".text = vclExample;
        "current-config/varnish.vcl".source = configFile;
      };

      flyingcircus.services.sensu-client.checks = {
        varnish_status = {
          notification = "varnishadm status reports errors";
          command = "${cfg.package}/bin/varnishadm -n ${cfg.stateDir} status";
          timeout = 180;
        };
        varnish_http = {
          notification = "varnish port 8008 HTTP response";
          command = "check_http -H localhost -p 8008 -c 10 -w 3 -t 20 -e HTTP";
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

      services.varnish = {
        enable = true;
        http_address = lib.concatMapStringsSep " -a "
          (addr: "${addr}:8008") fccfg.listenAddresses;
        config = varnishCfg;
      };

      systemd.services = {
        varnish = {
          stopIfChanged = false;
          path = with pkgs; [ varnish procps gawk ];
          reloadIfChanged = true;
          restartTriggers = [ configFile ];
          reload = ''
            if pgrep -a varnish | grep  -Fq '${varnishCmd}'
            then
              config=$(readlink -e /etc/current-config/varnish.vcl)
              # Varnish doesn't like slashes and numbers in config names.
              name=$(tr -dc 'a-z' <<< $config)
              varnishadm -n ${cfg.stateDir} vcl.list | grep -q $name && echo "Config unchanged." && exit
              varnishadm -n ${cfg.stateDir} vcl.load $name $config && varnishadm -n ${cfg.stateDir} vcl.use $name

              for vcl in $(varnishadm -n ${cfg.stateDir} vcl.list | grep ^available | awk {'print $5'});
              do
                varnishadm -n ${cfg.stateDir} vcl.discard $vcl
              done
            else
              echo "Binary or parameters changed. Restarting."
              systemctl restart varnish
            fi
          '';

          serviceConfig = {
            ExecStart = lib.mkOverride 90 varnishCmd;
            RestartSec = lib.mkOverride 90 "10s";
          };

        };
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
            ExecStart = "${cfg.package}/bin/varnishncsa -D -a -w /var/log/varnish.log -P /run/varnish/varnishncsa.pid -n ${cfg.stateDir}";
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
