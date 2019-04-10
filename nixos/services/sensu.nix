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
    else /var/empty;

  client_json = pkgs.writeText "client.json" ''
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

  config = mkIf cfg.enable {

    system.activationScripts.sensu-client = ''
      install -d -o sensuclient -g service -m 0775 \
        /etc/local/sensu-client /var/tmp/sensu /var/cache/vulnix
      install -d -o sensuclient -g service -m 0775 /var/cache/vulnix
      # 0 -> one file; 1 -> no files; 2 -> more than one file
      sensu_json_present=$(
        test -e /etc/local/sensu-client/*.json 2>/dev/null
        echo $?
      )
      if [[ $sensu_json_present != 1 ]]; then
        ${pkgs.fc.sensusyntax}/bin/fc-sensu-syntax -S
      fi
      unset sensu_json_present
    '';

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

    users.groups.sensuclient.gid = config.ids.gids.sensuclient;

    users.users.sensuclient = {
      description = "sensu client daemon user";
      uid = config.ids.uids.sensuclient;
      group = "sensuclient";
      # Allow sensuclient to interact with services, adm stuff and the journal.
      # This especially helps to check supervisor with a group-writable
      # socket:
      extraGroups = [ "service" "adm" "systemd-journal" ];
    };

    security.sudo.extraRules = [
      {
        commands = with pkgs; [
          "${fc.multiping}/bin/multiping"
          "${fc.sensuplugins}/bin/check_disk"
        ];
        groups = [ "sensuclient" ];
      }
    ];

    systemd.services.sensu-client = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      path = with pkgs; [
        bash
        coreutils
        fc.sensuplugins-rb
        glibc
        lm_sensors
        nagiosPluginsOfficial
        sensu
        sudo
        sysstat
      ];
      script = ''
        sensu-client -L ${cfg.loglevel} \
          -c ${client_json} \
          -d ${localSensuConf} \
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
      };
    };

    flyingcircus.services.sensu-client.checks = with pkgs;
    let
      uplink = ipvers: {
        notification = "Internet uplink IPv${ipvers} slow/unavailable";
        command =
          "${sudo} ${fc.multiping}/bin/multiping -${ipvers} " +
          "google.com dns.quad9.net heise.de";
        interval = 300;
      };

      debugBundlerEnv = pkgs.writeScript "debug-bundler-env" ''
        #!/nix/store/1hil95zzfqi62ldak5ijwjllf8j5yp0g-ruby-2.5.3/bin/ruby      
        # A modified debugging binstub based on the stub created by bundlerEnv.
        # Dumps out env vars to /tmp before and after running Bundler.setup().
        require 'yaml'

        # vars from original binstub
        ENV['BUNDLE_GEMFILE'] = "/nix/store/h098i6n5y9j9mkczaknav1da1rw0yx2x-gemfile-and-lockfile/Gemfile"
        ENV['BUNDLE_PATH'] = "/nix/store/fnwah9m69lj25ha2barzx1k84l9alsr8-sensuplugins-rb/lib/ruby/gems/2.5.0"
        ENV['BUNDLE_FROZEN'] = '1'

        # XXX: Messing around with env vars trying to create a env that works with nested Bundler.
        # XXX: Doesn't work currently. Included for reference purposes only.
        ENV['BUNDLE_BIN_PATH'] = '/nix/store/hpm2hmwbk1arhj26b34wkk1v3m732cr1-bundler-1.16.3/lib/ruby/gems/2.5.0/gems/bundler-1.16.3/exe/bundle'
        ENV['GEM_PATH'] = ""
        ENV['GEM_HOME'] = ENV['BUNDLE_PATH']
        ENV['BUNDLER_ORIG_BUNDLE_GEMFILE'] = ENV['BUNDLE_GEMFILE']
        ENV['BUNDLER_ORIG_PATH'] = 'BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL'
        ENV['PATH'] = '/nix/store/fnwah9m69lj25ha2barzx1k84l9alsr8-sensuplugins-rb/lib/ruby/gems/2.5.0/bin'

        env_to_delete = %w[
          EMBEDDED_RUBY
          INVOCATION_ID
          JOURNAL_STREAM
          LOGNAME
          LOCALE_ARCHIVE
          SENSU_LOADED_TEMPFILE
          BUNDLE_BIN_PATH
          BUNDLER_ORIG_BUNDLE_BIN_PATH
          BUNDLER_ORIG_BUNDLE_GEMFILE
          BUNDLER_ORIG_BUNDLER_ORIG_MANPATH
          BUNDLER_ORIG_BUNDLER_VERSION
          BUNDLER_ORIG_GEM_HOME
          BUNDLER_ORIG_GEM_PATH
          BUNDLER_ORIG_MANPATH
          BUNDLER_ORIG_PATH
          BUNDLER_ORIG_RB_USER_INSTALL
          BUNDLER_ORIG_RUBYLIB
          BUNDLER_ORIG_RUBYOPT
          BUNDLER_VERSION
          GEM_HOME
          GEM_PATH
          PATH
          RUBYLIB
          RUBYOPT
        ]
        env_to_delete.each { |e| ENV.delete(e) }

        Gem.use_paths("/nix/store/hpm2hmwbk1arhj26b34wkk1v3m732cr1-bundler-1.16.3/lib/ruby/gems/2.5.0", ENV["GEM_PATH"])

        File.write('/tmp/debugRb-before.yml', ENV.to_h.to_yaml)
        require 'bundler'
        Bundler.setup("default")

        File.write('/tmp/debugRb.yml', ENV.to_h.to_yaml)
        load Gem.bin_path("sensu-plugins-systemd", "check-failed-units.rb")
      '';

    in {
       # debug_bundled_ruby_checks = {
       #   command = "${debugBundlerEnv}";
       #   notification = "debugging Bundler, dumping vars locally...";
       #   interval = 60;
       # };

      load = {
        notification = "Load is too high";
        command =
          "check_load -r -w ${cfg.expectedLoad.warning} " +
          "-c ${cfg.expectedLoad.critical}";
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
      cpu_steal = {
        notification = "CPU has high amount of `%steal` ";
        command =
          "${fc.sensuplugins}/bin/check_cpu_steal " +
          "--mpstat ${sysstat}/bin/mpstat";
        interval = 600;
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
        command = "${fc.sensusyntax}/bin/fc-sensu-syntax";
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
        command = "check_uptime  -u minutes -c @:30 -w @:1440";
        interval = 300;
      };
      systemd_units = {
        notification = "systemd has failed units";
        command =
          "check-failed-units.rb -m logrotate.service " +
          "-m fc-collect-garbage.service";
      };
      disk = {
        notification = "Disk usage too high";
        command = "${sudo} ${fc.sensuplugins}/bin/check_disk -v -w 90 -c 95";
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
        command = "check-entropy.rb -w 120 -c 60";
      };
      local_resolver = {
        notification = "Local resolver not functional";
        command = "check-dns.rb -d ${config.networking.hostName}.gocept.net";
      };
      journal = {
        notification = "Journal errors in the last 10 minutes";
        command =
          "${fc.check-journal}/bin/check_journal " +
          "-j ${systemd}/bin/journalctl " +
          "https://bitbucket.org/flyingcircus/fc-logcheck-config/raw/tip/nixos-journal.yaml";
        interval = 600;
      };
      journal_file = {
        notification = "Journal file too small.";
        command = "${fc.sensuplugins}/bin/check_journal_file";
      };

      vulnix = {
        notification = "Security vulnerabilities in the last 6h";
        command =
          "NIX_REMOTE=daemon nice timeout 15m ${vulnix}/bin/vulnix --system " +
          "--cache-dir /var/cache/vulnix " +
          "-w https://raw.githubusercontent.com/flyingcircusio/vulnix.whitelist/master/fcio-whitelist.yaml " +
          "-w https://raw.githubusercontent.com/flyingcircusio/vulnix.whitelist/master/fcio-whitelist.toml ";
        interval = 6 * 3600;
      };

      manage = {
        notification = "The FC manage job is not enabled.";
        command = "${check_timer} fc-agent";
      };
      netstat_tcp = {
        notification = "Netstat TCP connections";
        command =
          "check-netstat-tcp.rb " +
          "-w ${toString cfg.expectedConnections.warning} " +
          "-c ${toString cfg.expectedConnections.critical}";
      };
      ethsrv_mtu = {
        notification = "ethsrv MTU @ 1500";
        command = "check-mtu.rb -i ethsrv -m 1500";
      };
      ethfe_mtu = {
        notification = "ethfe MTU @ 1500";
        command = "check-mtu.rb -i ethfe -m 1500";
      };
    };
  };

}
