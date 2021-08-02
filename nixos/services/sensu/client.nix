{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.flyingcircus.services.sensu-client;

  fclib = config.fclib;

  cores = fclib.currentCores 1;

  ntpServers = config.services.timesyncd.servers;

  sudo = "/run/wrappers/bin/sudo";

  check_timer = pkgs.writeScript "check-timer.sh" ''
    #!${pkgs.runtimeShell}
    timer=$1
    output=$(systemctl status $1.timer)
    result=$?
    echo "$output" | iconv -c -f utf-8 -t ascii
    exit $(( result != 0 ? 2 : 0 ))
  '';

  localSensuConf =
    if pathExists "/etc/local/sensu-client"
    then cleanSourceWith {
      filter = name: _: (baseNameOf name) != "README.txt";
      src = /etc/local/sensu-client;
    }
    else "/var/empty";

  sensuClientConfigFile = pkgs.writeText "client.json" ''
    {
      "_comment": [
        "This is a comment to help restarting sensu when necessary.",
        "Active Groups: ${toString config.users.users.sensuclient.extraGroups}"
      ],
      "client": {
        "name": "${config.networking.hostName}",
        "address": "${config.networking.hostName}",
        "subscriptions": ["default"],
        "signature": "${cfg.password}"
      },
      "rabbitmq": {
        "host": "${cfg.server}",
        "user": "${config.networking.hostName}.gocept.net",
        "password": "${cfg.password}",
        "vhost": "/sensu"
      },
      "checks": ${builtins.toJSON
        (mapAttrs (
          name: value: filterAttrs (
            name: value: name != "_module") value) cfg.checks)}
    }
  '';

  ifJsonSyntaxError = ''
    sensu_json_present=$(
      # tricky exit code:
      # 0 -> one file; 1 -> no files; 2 -> more than one file
      test -e /etc/local/sensu-client/*.json 2>/dev/null
      echo $?
    )
    if [[ $sensu_json_present != 1 ]] && ! ${sensusyntax} -S; then
  '';

  sensusyntax = "${pkgs.fc.sensusyntax}/bin/fc-sensu-syntax";

  checkOptions = {
    options = {
      notification = mkOption {
        type = types.str;
        description = "The notification on events.";
      };
      command = mkOption {
        type = types.str;
        description = "The command to execute as the check.";
      };
      interval = mkOption {
        type = types.int;
        default = 60;
        description = "The interval (in seconds) how often this check should be performed.";
      };
      timeout = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "The timeout when the client should abort the check and consider it failed.";
      };
      ttl = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "The time after which a check result should be considered stale and cause an event.";
      };
      standalone = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to schedule this check autonomously on the client.";
      };
      warnIsCritical = mkOption {
        type = types.bool;
        default = false;
        description = "Whether a warning of this check should be escalated to critical by our status page.";
      };
    };
  };

  sensuCheckEnv = pkgs.buildEnv {
    name = "sensu-check-env";
    paths = cfg.checkEnvPackages;
  };

in {
  options = {

    flyingcircus.services.sensu-client = {
      enable = mkEnableOption "Sensu monitoring client daemon";

      server = mkOption {
        type = types.str;
        description = ''
          The address of the server (RabbitMQ) to connect to.
        '';
      };
      loglevel = mkOption {
        type = types.str;
        default = "warn";
        description = ''
          The level of logging.
        '';
      };
      password = mkOption {
        type = types.str;
        description = ''
          The password to connect with to server (RabbitMQ).
        '';
      };
      config = mkOption {
        type = types.lines;
        description = ''
          Contents of the sensu client configuration file.
        '';
      };
      checks = mkOption {
        default = {};
        type = with types; attrsOf (submodule checkOptions);
        description = ''
          Checks that should be run by this client.
          Defined as attribute sets that conform to the JSON structure
          defined by Sensu: <https://sensuapp.org/docs/latest/checks>.
        '';
      };

      checkEnvPackages = mkOption {
        type = with types; listOf package;
        description = ''
          List of packages to include in the PATH visible in Sensu checks.
          This can be used to add custom check scripts or external programs
          you want to call from your check.
        '';
      };

      extraOpts = mkOption {
        type = with types; listOf str;
        default = [];
        description = ''
          Extra options used when launching sensu.
        '';
      };
      expectedConnections = {
        warning = mkOption {
          type = types.int;
          description = ''
            Set the warning limit for connections on this host.
          '';
          default = 5000;
        };
        critical = mkOption {
          type = types.int;
          description = ''
            Set the critical limit for connections on this host.
          '';
          default = 6000;
        };
      };
      expectedDiskCapacity = {
        warning = mkOption {
          type = types.int;
          description = ''
            Set the warning limit for disk capacity on this host.
          '';
          default = 90;
        };
        critical = mkOption {
          type = types.int;
          description = ''
            Set the critical limit for disk capacity on this host.
          '';
          default = 95;
        };
      };
      expectedLoad = {
        warning = mkOption {
          type = types.str;
          default =
            "${toString (cores * 8)},${toString (cores * 5)}," +
            "${toString (cores * 2)}";
          description = "Limit of load thresholds before warning.";
        };
        critical = mkOption {
          type = types.str;
          default =
            "${toString (cores * 10)},${toString (cores * 8)}," +
            "${toString (cores * 3)}";
          description = "Limit of load thresholds before reaching critical.";
        };
      };
      expectedSwap = {
        warning = mkOption {
          type = types.int;
          default = 1024;
          description = "Limit of swap usage in MiB before warning.";
        };
        critical = mkOption {
          type = types.int;
          default = 2048;
          description = "Limit of swap usage in MiB before reaching critical.";
        };
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {

      environment.systemPackages = [
        (pkgs.writeScriptBin
          "sensu-check-env"
          "echo ${sensuCheckEnv}/bin/")
        (pkgs.writeScriptBin
          "sensu-client-show-config"
          "${pkgs.perl}/bin/json_pp < ${sensuClientConfigFile}")
      ];

      flyingcircus.passwordlessSudoRules = [
        {
          commands = with pkgs; [
            "${fc.multiping}/bin/multiping"
            "${fc.sensuplugins}/bin/check_disk"
          ];
          groups = [ "sensuclient" ];
        }
        # Allow sensuclient group to become service user for running custom checks
        {
          commands = [ "ALL" ];
          groups = [ "sensuclient" ];
          runAs = "%service";
        }
      ];

      flyingcircus.activationScripts = {
        sensu-client = ''
          ${ifJsonSyntaxError}
            echo "Errors in /etc/local/sensu-client, aborting"
            exit 3
          fi
          unset sensu_json_present
        '';
      };

      flyingcircus.services.sensu-client.checkEnvPackages = with pkgs; [
        bash
        coreutils
        glibc
        lm_sensors
        monitoring-plugins
        nix
        openssl
        procps
        python3
        sensu
        sensu-plugins-disk-checks
        sensu-plugins-http
        sensu-plugins-influxdb
        sensu-plugins-logs
        sysstat
      ];

      systemd.services.sensu-client = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        stopIfChanged = false;
        # Sensu check scripts inherit the PATH of sensu-client by default.
        # We provide common external dependencies in sensuCheckEnv.  Checks can
        # define their own PATH in a wrapper to include other dependencies.
        path = [ sensuCheckEnv "/run/wrappers" ];
        script = ''
          ${ifJsonSyntaxError}
            # graceful degradation -> leave local config out
            confDir=""
          else
            confDir="-d ${localSensuConf}"
          fi
          # omit localSensuConf dir if syntax errors have been detected
          exec sensu-client -L ${cfg.loglevel} \
            -c ${sensuClientConfigFile} $confDir \
            ${concatStringsSep " " cfg.extraOpts}
        '';
        serviceConfig = {
          User = "sensuclient";
          Group = "sensuclient";
          Restart = "always";
          RestartSec = "5s";
        };
        environment = {
          LANG = "en_US.utf8";
          # Hide annoying warnings, old Sensu is not developed anymore.
          RUBYOPT="-W0";
        };
      };

      systemd.tmpfiles.rules = [
        "d /var/tmp/sensu 0775 sensuclient service"
      ];

      flyingcircus.services.sensu-client.checks = with pkgs;
      let
        uplink = ipvers: {
          notification = "Internet uplink IPv${ipvers} slow/unavailable";
          command =
            "${sudo} ${fc.multiping}/bin/multiping -${ipvers} " +
            "google.com dns.quad9.net heise.de";
          interval = 300;
        };
      in {
        load = {
          notification = "Load is too high";
          command =
            "check_psi cpu " +
            "--some-warning 5" +
            "--some-critical 10" +
            "--full-warning ${cfg.expectedLoad.warning}" +
            "--full-critical ${cfg.expectedLoad.critical}";
          interval = 10;
        };
        swap = {
          notification = "Swap usage is too high";
          command =
            "${fc.sensuplugins}/bin/check_swap_abs " +
            "-w ${toString cfg.expectedSwap.warning} " +
            "-c ${toString cfg.expectedSwap.critical}";
          interval = 300;
        };
        ssh = {
          notification = "SSH server is not responding properly";
          command = "check_ssh localhost";
          interval = 300;
        };
        ntp_time = {
          notification = "Clock is skewed";
          command = "check_ntp_time -H ${elemAt ntpServers 0}";
          interval = 300;
        };
        sensu_syntax = {
          notification = ''
            Problematic check definitions in /etc/local/sensu-client
          '';
          command = sensusyntax;
          interval = 60;
        };
        internet_uplink_ipv4 = uplink "4";
        internet_uplink_ipv6 = uplink "6";
        # Signal for 30 minutes that it was not OK for the VM to reboot. We may
        # need something to counter this on planned reboots. 30 minutes is enough
        # for status pages to pick this up. After that, we'll leave it in "warning"
        # for 1 day so that regular support can spot the issue even if it didn't
        # cause an alarm, but have it visible for context.
        uptime = {
          notification = "Host was down";
          command = "${check-uptime}/bin/check_uptime -c @:30 -w @:1440";
          interval = 300;
        };
        systemd_units = {
          notification = "systemd has failed units";
          command = ''
            ${pkgs.sensu-plugins-systemd}/bin/check-failed-units.rb \
              -m logrotate.service \
              -m fc-collect-garbage.service
          '';
        };
        disk = {
          notification = "Disk usage too high";
          command = "${sudo} ${fc.sensuplugins}/bin/check_disk -v " +
                    "-w ${toString cfg.expectedDiskCapacity.warning} " +
                    "-c ${toString cfg.expectedDiskCapacity.critical}";
          interval = 300;
        };
        writable = {
          notification = "Disks are writable";
          command =
            "${fc.sensuplugins}/bin/check_writable /tmp/.sensu_writable " +
            "/var/tmp/sensu/.sensu_writable";
          interval = 60;
          ttl = 120;
          warnIsCritical = true;
        };
        entropy = {
          notification = "Too little entropy available";
          command = ''
            ${pkgs.sensu-plugins-entropy-checks}/bin/check-entropy.rb \
              -w 120 -c 60
          '';
        };
        journal = {
          notification = "Journal errors in the last 10 minutes";
          command =
            "${fc.check-journal}/bin/check_journal " +
            "-j ${systemd}/bin/journalctl " +
            "https://gitlab.flyingcircus.io/flyingcircus/fc-logcheck-config/" +
            "raw/master/nixos-journal.yaml";
          interval = 600;
        };
        journal_file = {
          notification = "Journal file too small.";
          command = "${fc.sensuplugins}/bin/check_journal_file";
        };
        manage = {
          notification = "The FC manage job is not enabled.";
          command = "${check_timer} fc-agent";
        };
        netstat_tcp = {
          notification = "Netstat TCP connections";
          command = ''
            ${pkgs.sensu-plugins-network-checks}/bin/check-netstat-tcp.rb \
              -w ${toString cfg.expectedConnections.warning} \
              -c ${toString cfg.expectedConnections.critical}
          '';
        };
        obsolete-result-links = {
          notification = ''
            Obsolete 'result' symlinks possibly causing Nix store bloat
          '';
          # see also activationScript in nixos/platform/agent.nix
          command = "${fc.check-age}/bin/check_age -m -w 3h /result /root/result";
          interval = 300;
        };
        root_lost_and_found = {
          notification = ''
            lost+found indicating filesystem issues on /
          '';
          command = "${fc.check-age}/bin/check_age -m /lost+found -w 2h -c 1d";
          interval = 300;
        };
      };
    })

    {
      # Config that should always be available to allow deployments to
      # succeed even if no real sensu environment is available.

      environment.etc."local/sensu-client/README.txt".text = ''
        Put local sensu checks here.

        This directory is passed to sensu as additional config directory. You
        can add .json files for your checks.

        Example:

          {
           "checks" : {
              "my-custom-check" : {
                 "notification" : "custom check broken",
                 "command" : "/srv/user/bin/nagios_compatible_check",
                 "interval": 60,
                 "standalone" : true
              },
              "my-other-custom-check" : {
                 "notification" : "custom check broken",
                 "command" : "/srv/user/bin/nagios_compatible_other_check",
                 "interval": 600,
                 "standalone" : true
              }
            }
          }
      '';

      flyingcircus.localConfigDirs.sensu-client = {
        dir = "/etc/local/sensu-client";
        user = "sensuclient";
      };

      users.groups.sensuclient.gid = config.ids.gids.sensuclient;

      users.users.sensuclient = {
        description = "sensu client daemon user";
        uid = config.ids.uids.sensuclient;
        group = "sensuclient";
        isSystemUser = true;
        # Allow sensuclient to interact with services, adm stuff and the journal.
        # This especially helps to check supervisor with a group-writable
        # socket:
        extraGroups = [ "service" "adm" "systemd-journal" ];
      };
    }
  ];
}
