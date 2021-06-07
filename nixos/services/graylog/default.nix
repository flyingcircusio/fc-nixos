{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.services.graylog;
  fclib = config.fclib;

  listenFQDN = "${config.networking.hostName}.${config.networking.domain}";
  # graylog listens on first srv ipv6 address
  listenIP = (head config.networking.interfaces.ethsrv.ipv6.addresses).address;
  # FQDN doesn't work here
  httpBindAddress = "[${listenIP}]:${toString cfg.apiPort}";
  webListenUri = "http://${listenFQDN}:${toString cfg.apiPort}";
  restListenUri = "${webListenUri}/api";

  glNodes =
    fclib.listServiceAddresses "loghost-server" ++
    fclib.listServiceAddresses "graylog-server";

  glPlugins = pkgs.buildEnv {
    name = "graylog-plugins";
    paths = cfg.plugins;
  };

  # Secrets can be set in advance (for example, to share a password across nodes).
  # Missing files will be generated when the graylog service starts.

  # This password can be used to login with the admin user.
  rootPasswordFile = "/etc/local/graylog/password";
  passwordSecretFile = "/etc/local/graylog/password_secret";

  rootPassword = fclib.servicePassword {
    user = cfg.user;
    file = rootPasswordFile;
    token = config.networking.hostName;
  };

  passwordSecret = fclib.servicePassword {
    user = cfg.user;
    file = passwordSecretFile;
    token = config.networking.hostName;
  };

  graylogShowConfig = pkgs.writeScriptBin "graylog-show-config" ''
    cat /run/graylog/graylog.conf
  '';

  defaultGraylogConfig = let
    slash = addr: if fclib.isIp4 addr then "/32" else "/128";
    otherGraylogNodes =
      filter
        (a: elem "${a.name}.${config.networking.domain}" glNodes)
        config.flyingcircus.encAddresses;

  in {
    http_bind_address = httpBindAddress;
    http_publish_uri = webListenUri;
    timezone = config.time.timeZone;

    processbuffer_processors =
      fclib.max [
        ((fclib.currentCores 1) - 2)
        5
      ];

    outputbuffer_processors =
      fclib.max [
        ((fclib.currentCores 1) / 2)
        3
      ];
  } //
  lib.optionalAttrs (otherGraylogNodes != []) {
    trusted_proxies =
      concatMapStringsSep
        ", "
        (a: (fclib.stripNetmask a.ip) + (slash a.ip))
        otherGraylogNodes;
  };

  graylogConf = let
      mkLine = name: value: "${name} = ${toString value}";
    in ''
      is_master = ${lib.boolToString cfg.isMaster}
      node_id_file = ${cfg.nodeIdFile}
      elasticsearch_hosts = ${lib.concatStringsSep "," cfg.elasticsearchHosts}
      message_journal_dir = ${cfg.messageJournalDir}
      mongodb_uri = ${cfg.mongodbUri}
      plugin_dir = /var/lib/graylog/plugins

      # secrets
      root_password_sha2 = $(sha256sum ${rootPassword.file} | cut -f1 -d " ")
      password_secret = $(cat "${passwordSecret.file}")

      # disable version check as its really annoying and obscures real errors
      versionchecks = false

      # Settings here can be overridden by flyingcircus.services.graylog.config.
    '' + lib.concatStringsSep
            "\n"
            (lib.mapAttrsToList
              mkLine
                (defaultGraylogConfig // cfg.config));

  graylogConfPath = "/run/graylog/graylog.conf";

  telegrafUsername = "telegraf-${config.networking.hostName}";
  telegrafPassword = fclib.derivePasswordForHost "graylog-telegraf";

in {

  options = with lib; {

    flyingcircus.services.graylog = {

      enable = mkEnableOption "Preconfigured Graylog (3.x).";

      package = mkOption {
        type = types.package;
        default = pkgs.graylog;
        defaultText = "pkgs.graylog";
        example = literalExample "pkgs.graylog";
        description = "Graylog package to use.";
      };

      user = mkOption {
        type = types.str;
        default = "graylog";
        example = literalExample "graylog";
        description = "User account under which graylog runs";
      };

      isMaster = mkOption {
        type = types.bool;
        default = true;
        description = "Use this graylog node as master. Only one master per cluster is allowed.";
      };

      nodeIdFile = mkOption {
        type = types.str;
        default = "/var/lib/graylog/server/node-id";
        description = "Path of the file containing the graylog node-id";
      };

      elasticsearchHosts = mkOption {
        type = types.listOf types.str;
        example = literalExample ''[ "http://node1:9200" "http://user:password@node2:19200" ]'';
        description = "List of valid URIs of the http ports of your elastic nodes. If one or more of your elasticsearch hosts require authentication, include the credentials in each node URI that requires authentication";
      };

      messageJournalDir = mkOption {
        type = types.str;
        default = "/var/lib/graylog/data/journal";
        description = "The directory which will be used to store the message journal. The directory must be exclusively used by Graylog and must not contain any other files than the ones created by Graylog itself";
      };

      mongodbUri = mkOption {
        type = types.str;
        default = "mongodb://localhost/graylog";
        description = "MongoDB connection string. See http://docs.mongodb.org/manual/reference/connection-string/ for details";
      };

      plugins = mkOption {
        description = "Extra graylog plugins";
        default = with pkgs.graylogPlugins; [ slack ];
        type = types.listOf types.package;
      };

      heapPercentage = mkOption {
        type = types.int;
        default = 70;
        description = "How much RAM should go to graylog heap.";
      };

      beatsTCPGraylogPort = mkOption {
        type = types.int;
        default = 12302;
      };

      gelfTCPGraylogPort = mkOption {
        type = types.int;
        default = 12202;
      };

      apiPort = mkOption {
        type = types.int;
        default = 9001;
      };

      syslogInputPort = mkOption {
        type = types.int;
        default = 5140;
        description = "UDP Port for the Graylog syslog input.";
      };

      config = mkOption {
        type = types.attrs;
        default = {};
        description = ''
          Additional config params for the Graylog server config file.
          They override default settings defined by this service with the same name.
        '';
      };
    };
  };


  config = lib.mkIf cfg.enable {

    users.users = lib.mkIf (cfg.user == "graylog") {
      graylog = {
        uid = config.ids.uids.graylog;
        description = "Graylog server daemon user";
      };
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.messageJournalDir}' - ${cfg.user} - - -"
      "d '/run/graylog' - ${cfg.user} - - -"
      # Purge geolite DB that has been created by a timer in earlier releases.
      "r /var/lib/graylog/GeoLite2-City.mmdb"
    ];

    environment.etc."local/graylog/api_url".text = restListenUri;

    environment.systemPackages = [ graylogShowConfig ];

    systemd.services.graylog = {

      description = "Graylog Server";
      wantedBy = [ "multi-user.target" ];
      environment = let
        pkg = config.services.graylog.package;
        javaHeap = ''${toString
          (fclib.max [
            ((fclib.currentMemory 1024) * cfg.heapPercentage / 100)
            768
            ])}m'';

        javaOpts = [
          "-Djava.library.path=${pkg}/lib/sigar"
          "-Dlog4j.configurationFile=file://${./log4j2.xml}"
          "-Xms${javaHeap}"
          "-Xmx${javaHeap}"
          "-XX:NewRatio=1"
          "-server"
          "-XX:+ResizeTLAB"
          "-XX:+UseConcMarkSweepGC"
          "-XX:+CMSConcurrentMTEnabled"
          "-XX:+CMSClassUnloadingEnabled"
          "-XX:+UseParNewGC"
          "-XX:-OmitStackTraceInFastThrow"
        ];

      in {
        JAVA_HOME = pkgs.jre_headless;
        GRAYLOG_CONF = graylogConfPath;
        JAVA_OPTS = lib.concatStringsSep " " javaOpts;
      };

      path = [ pkgs.jre_headless pkgs.which pkgs.procps ];

      preStart = ''
        rm -rf /var/lib/graylog/plugins || true
        mkdir -p /var/lib/graylog/plugins -m 755

        mkdir -p "$(dirname ${cfg.nodeIdFile})"
        chown -R ${cfg.user} "$(dirname ${cfg.nodeIdFile})"

        for declarativeplugin in `ls ${glPlugins}/bin/`; do
          ln -sf ${glPlugins}/bin/$declarativeplugin /var/lib/graylog/plugins/$declarativeplugin
        done
        for includedplugin in `ls ${cfg.package}/plugin/`; do
          ln -s ${cfg.package}/plugin/$includedplugin /var/lib/graylog/plugins/$includedplugin || true
        done

        # Generate secrets if missing and write config file

        ${rootPassword.generate}
        ${passwordSecret.generate}

        cat > ${graylogConfPath} << EOF
        ${graylogConf}
        EOF

        chown ${cfg.user}:service ${graylogConfPath}
        chmod 440 ${graylogConfPath}
      '';

      postStart = ''
        # Wait until GL is available for use
        for count in {0..10000}; do
            ${pkgs.curl}/bin/curl -m 2 -s ${webListenUri} && exit
            echo "Trying to connect to ${webListenUri} for ''${count}s"
            sleep 1
        done
        exit 1
      '';

      serviceConfig = {
        Restart = "always";
        # Starting just takes a long time...
        TimeoutStartSec = 360;
        PermissionsStartOnly = true;
        User = "${cfg.user}";
        StateDirectory = "graylog";
        ExecStart = "${cfg.package}/bin/graylogctl run";
      };

    };

    systemd.services.fc-graylog-config = {
      description = "Configure Graylog FCIO settings";
      requires = [ "graylog.service" ];
      after = [ "graylog.service" "mongodb.service" "elasticsearch.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = config.services.graylog.user;
        RemainAfterExit = true;
      };
      script = let

        syslogUdpConfiguration = {
          configuration = {
            bind_address = "0.0.0.0";
            port = cfg.syslogInputPort;
          };
          title = "Syslog UDP"; # be careful changing it, it's used as
                                # a primary key for identifying the config
                                # object
          type = "org.graylog2.inputs.syslog.udp.SyslogUDPInput";
          global = true;
        };

        gelfTcpConfiguration = {
          configuration = {
            bind_address = "0.0.0.0";
            port = cfg.gelfTCPGraylogPort;
          };
          title = "GELF TCP";
          type = "org.graylog2.inputs.gelf.tcp.GELFTCPInput";
          global = true;
        };

        beatsTcpConfiguration = {
          configuration = {
            bind_address = "0.0.0.0";
            no_beats_prefix = true;
            port = cfg.beatsTCPGraylogPort;
          };
          title = "Beats TCP";
          type = "org.graylog.plugins.beats.Beats2Input";
          global = true;
        };

        geodbConfiguration = {
          enabled = true;
          db_type = "MAXMIND_CITY";
          db_path = "/var/lib/graylog/GeoLite2-City.mmdb";
        };

        ldapConfiguration = {
            enabled = true;
            system_username = fclib.getLdapNodeDN;
            system_password = fclib.getLdapNodePassword;
            ldap_uri = "ldaps://ldap.fcio.net:636/";
            trust_all_certificates = true;
            use_start_tls = false;
            active_directory = false;
            search_base = "ou=People,dc=gocept,dc=com";
            search_pattern = "(&(&(objectClass=inetOrgPerson)(uid={0}))(memberOf=cn=${config.flyingcircus.enc.parameters.resource_group},ou=GroupOfNames,dc=gocept,dc=com))";
            display_name_attribute = "displayName";
            default_group = "Admin";
        };

        metricsRole = {
          description = "Provides read access to all system metrics";
          permissions = ["metrics:*"];
          read_only = false;
        };

        telegrafUser = {
          password = telegrafPassword;
          roles = [ "Metrics" ];
        };

        callApi = what: "${pkgs.fc.agent}/bin/fc-graylog ${what}";

        configureInput = input:
          callApi "configure --input '${toJSON input}'";
      in ''
        ${configureInput syslogUdpConfiguration}
        ${configureInput gelfTcpConfiguration}
        ${configureInput beatsTcpConfiguration}

        ${callApi ''
          call \
          -s 202 \
          /system/cluster_config/org.graylog.plugins.map.config.GeoIpResolverConfig \
          '${toJSON geodbConfiguration}'
        ''}

        ${callApi ''
          call \
          -s 204 \
          /system/ldap/settings \
          '${toJSON ldapConfiguration}'
        ''}

        ${callApi "ensure-role Metrics '${toJSON metricsRole}'"}

        ${callApi "ensure-user ${telegrafUsername} '${toJSON telegrafUser}'"}
      '';
    };

    systemd.services.graylog-collect-journal-age-metric = rec {
      description = "Collect journal age and report to Telegraf";
      wantedBy = [ "graylog.service" "telegraf.service" "fc-graylog-config.service" ];
      after = wantedBy;
      serviceConfig = {
        User = "telegraf";
        Restart = "always";
        RestartSec = "10";
        ExecStart = ''
          ${pkgs.fc.agent}/bin/fc-graylog \
            -u ${telegrafUsername} \
            -p '${telegrafPassword}' \
            collect-journal-age-metric --socket-path /run/telegraf/influx.sock

        '';
      };
    };

    services.collectd.extraConfig = ''
      LoadPlugin curl_json
      <Plugin curl_json>
        <URL "${restListenUri}/system/journal">
          User "admin"
          Password "${rootPassword.value}"
          Header "Accept: application/json"
          Instance "graylog"
          <Key "uncommitted_journal_entries">
            Type "gauge"
          </Key>
          <Key "append_events_per_second">
            Type "gauge"
          </Key>
          <Key "read_events_per_second">
            Type "gauge"
          </Key>
        </URL>
        <URL "${restListenUri}/system/throughput">
          User "admin"
          Password "${rootPassword.value}"
          Header "Accept: application/json"
          Instance "graylog"
          <Key "throughput">
            Type "gauge"
          </Key>
        </URL>
      </Plugin>
    '';

    flyingcircus.services.sensu-client.checks = {

      graylog_ui = {
        notification = "Graylog UI alive";
        command = ''
          ${pkgs.monitoring-plugins}/bin/check_http \
            -H ${listenFQDN} -p ${toString cfg.apiPort} \
            -u /
        '';
      };

    };

    flyingcircus.services.telegraf.inputs.graylog = [
      {
        servers = [ "${restListenUri}/system/metrics/multiple" ];
        metrics = [ "jvm.memory.total.committed"
                    "jvm.memory.total.used"
                    "jvm.threads.count"
                    "org.graylog2.buffers.input.size"
                    "org.graylog2.buffers.input.usage"
                    "org.graylog2.buffers.output.size"
                    "org.graylog2.buffers.output.usage"
                    "org.graylog2.buffers.process.size"
                    "org.graylog2.buffers.process.usage"
                    "org.graylog2.journal.oldest-segment"
                    "org.graylog2.journal.size"
                    "org.graylog2.journal.size-limit"
                    "org.graylog2.throughput.input"
                    "org.graylog2.throughput.output" ];
        username = telegrafUsername;
        password = telegrafPassword;
      }
    ];
  };

}
