# Wazuh agent — the host side of the Wazuh security monitoring platform.
# Agents collect security events (file integrity, log data, system
# inventory) and report to a central Wazuh manager for analysis
# (https://documentation.wazuh.com/current/getting-started/components/wazuh-agent.html).
# Deliberately observe-only: services run as an unprivileged user by
# default, so commands pushed by the manager (active response, restarts)
# execute without privileges and capabilities and cannot change the host
# (active responses like firewall-drop are ineffective).
#
# Enrollment flow:
#   1. setup-pre-wazuh (root) — copies package state dirs, config, and auth password
#      into /var/ossec/. Runs only when wazuh-agent-auth is triggered.
#   2. wazuh-agent-auth (wazuh user) — runs `agent-auth` to register the agent
#      with the manager. Skipped if /var/ossec/.agent-registered exists.
#   3. Daemon services start.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    mkPackageOption
    mkIf
    mapAttrs
    mapAttrsToList
    nameValuePair
    listToAttrs
    concatMapStringsSep
    filterAttrsRecursive
    types
    ;

  # Filter null values from settings to avoid empty XML elements
  # Wazuh's XML parser doesn't handle <tag></tag> well for optional fields
  filterNulls = filterAttrsRecursive (_: v: v != null);

  format = pkgs.formats.xml { withHeader = false; };

  stateDir = "/var/ossec";
  cfg = config.services.wazuh.agent;

  # Per-daemon group/capabilities separation, granted per-service so
  # non-daemon processes running as this user (e.g. agent-auth) carry
  # nothing. The file readers (FIM, log files, inventory) share
  # CAP_DAC_READ_SEARCH; the notes below cover the rest.
  daemons = {
    "wazuh-modulesd" = {
      # syscollector reads /sys and rtnetlink — no systemd-network
      # group needed; re-add it here if network inventory gaps show up.
      description = "Wazuh agent modules (system inventory, SCA, ...)";
      capabilities = [ "CAP_DAC_READ_SEARCH" ];
      supplementaryGroups = [ ];
    };
    "wazuh-logcollector" = {
      # journald source — the only daemon needing the journal group.
      description = "Log data collection";
      capabilities = [ "CAP_DAC_READ_SEARCH" ];
      supplementaryGroups = [ "systemd-journal" ];
    };
    "wazuh-syscheckd" = {
      # rootcheck's check_ports binds privileged ports to detect hidden
      # listeners. Whodata FIM (audit/eBPF) is deliberately unsupported:
      # CAP_AUDIT_CONTROL/CAP_BPF are absent, and the Wazuh agent
      # silently falls back to realtime (inotify).
      description = "File integrity monitoring and rootcheck";
      capabilities = [
        "CAP_DAC_READ_SEARCH"
        "CAP_NET_BIND_SERVICE"
      ];
      supplementaryGroups = [ ];
    };
    "wazuh-agentd" = {
      # Pure network client.
      description = "Manager connection";
      capabilities = [ ];
      supplementaryGroups = [ ];
    };
    "wazuh-execd" = {
      # Active response deliberately unprivileged — commands like
      # firewall-drop cannot take effect.
      description = "Active response execution";
      capabilities = [ ];
      supplementaryGroups = [ ];
    };
  };

  mkService = name: spec: {
    description = spec.description;
    documentation = [
      "https://documentation.wazuh.com/${lib.versions.majorMinor cfg.package.version}/user-manual/reference/daemons/${name}.html"
    ];
    unitConfig.RequiresMountsFor = [ stateDir ];

    wants = [ "setup-pre-wazuh.service" ];
    after = [ "setup-pre-wazuh.service" ];

    partOf = [ "wazuh.target" ];
    # The daemons read their config from the compiled-in path
    # /var/ossec/etc/ossec.conf, which the unit never references —
    # so settings changes need an explicit restart trigger.
    restartTriggers = [ cfg.config ];
    path =
      cfg.defaultPackages
      ++ cfg.extraPackages
      ++ [
        "/run/current-system/sw/bin"
      ];
    environment = {
      WAZUH_HOME = stateDir;
    };

    serviceConfig = {
      Type = "exec";
      User = cfg.user;
      Group = cfg.group;
      SupplementaryGroups = spec.supplementaryGroups;
      WorkingDirectory = "${stateDir}/";
      AmbientCapabilities = spec.capabilities;
      CapabilityBoundingSet = spec.capabilities;

      ExecStart = "${cfg.package}/bin/${name} -f";

      # Crashes are expected (self-healing): retry every 5s. With this
      # spacing the default start rate limit (5 starts/10s) can never trip.
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
in
{
  options = {
    services.wazuh.agent = {
      enable = mkEnableOption "the Wazuh agent, which monitors the host and reports to a central Wazuh manager";
      package = mkPackageOption pkgs "wazuh-agent" { };

      user = mkOption {
        type = types.str;
        default = "wazuh";
        description = "User to run the wazuh daemons as.";
      };
      group = mkOption {
        type = types.str;
        default = "wazuh";
        description = "Group to run the wazuh daemons under.";
      };
      config = mkOption {
        type = types.path;
        readOnly = true;
        internal = true;
        description = "Final `ossec.conf` configuration file used by wazuh";
        # Root element must be <ossec_config> — Wazuh's parser expects
        # exactly this tag name (the attrset key becomes the XML root).
        default = format.generate "ossec.conf" {
          ossec_config = filterNulls cfg.settings;
        };
      };

      settings = mkOption {
        default = { };
        description = ''
          Wazuh-agent configuration written in Nix. This will be serialized
          to XML and passed as `ossec.conf`

          Note that the root `ossec_config` tag is added automatically

          Not all possible configuration options are listed here - see the
          [config reference](https://documentation.wazuh.com/${lib.versions.majorMinor cfg.package.version}/user-manual/reference/ossec-conf/index.html)
          for possible values. The package ships a complete, version-matching
          example at `etc/ossec.conf`
        '';
        type = types.submodule {
          freeformType = format.type;

          options = {
            client = {
              server = {
                address = mkOption {
                  type = types.nonEmptyStr;
                  description = ''
                    Specifies the IP address or the hostname of the Wazuh manager.
                  '';
                  example = "192.168.1.2";
                };
                port = mkOption {
                  type = types.port;
                  description = ''
                    Specifies the port to send events to the manager. This
                    must match the associated listening port configured on
                    the Wazuh manager.
                  '';
                  default = 1514;
                };
              };
              enrollment = {
                port = mkOption {
                  type = types.port;
                  description = ''
                    Specifies the port on the manager to send enrollment
                    request. This must match the associated listening port
                    configured on the Wazuh manager.
                  '';
                  default = 1515;
                };
              };
            };
          };
        };
      };

      defaultPackages = mkOption {
        type = types.listOf types.package;
        default = with pkgs; [
          util-linux
          coreutils-full
          nettools
          ps
        ];
        defaultText = ''
          with pkgs; [
            util-linux
            coreutils-full
            nettools
            ps
          ];
        '';
        example = "lib.mkForce []";
        description = ''
          List of packages added to wazuh-agent's `$PATH` by default.
          These can be removed/overridden with `lib.mkForce`.
          To add additional packages, use
          `services.wazuh.agent.extraPackages` instead.
        '';
      };
      extraPackages = mkOption {
        type = types.listOf types.package;
        default = [ ];
        example = lib.literalExpression "[ pkgs.hello ]";
        description = "List of extra packages added to wazuh-agent's `$PATH`";
      };

      agentAuthPassword = mkOption {
        type = types.nullOr types.nonEmptyStr;
        default = null;
        description = ''
          Password for the manager auth service, used only for initial
          enrollment — after successful registration, changing it has no
          effect. `agent-auth` reads the password from
          `/var/ossec/etc/authd.pass`
          ([password authentication](https://documentation.wazuh.com/${lib.versions.majorMinor cfg.package.version}/user-manual/agent/agent-enrollment/security-options/using-password-authentication.html)):
          set this option, or place that file there manually as
          `wazuh:wazuh` with mode `0640` (the setup service enforces
          both on its next run).

          Note: the option value ends up world-readable in the Nix store
          and the generated system configuration (stopgap until the
          platform secret (KV) store can provision enrollment secrets);
          the blast radius is limited to superfluous agent registrations
          on the manager.
        '';
      };

      agentAuthGroup = mkOption {
        type = types.nullOr types.nonEmptyStr;
        default = null;
        description = ''
          Agent group assigned during enrollment (`-G` flag to agent-auth).
          The agent will be added to this group on the manager after
          registration.

          The group must already exist on the manager — it is not created,
          and enrollment fails for an unknown group. Like
          `agentAuthPassword`, this only applies to the initial enrollment:
          to change an enrolled agent's group, use `agent_groups` on the
          manager ([agent grouping](https://documentation.wazuh.com/${lib.versions.majorMinor cfg.package.version}/user-manual/agent/agent-management/grouping-agents.html)).
        '';
        example = "VM";
      };
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
      description = "Wazuh agent user";
      home = stateDir;
    };

    users.groups.${cfg.group} = { };

    systemd = {
      tmpfiles.rules = [
        "d ${stateDir}/tmp 0750 ${cfg.user} ${cfg.group} 1d"
      ];
      targets.wazuh = {
        description = "Wazuh agent";
        wantedBy = [ "multi-user.target" ];
        wants = mapAttrsToList (name: _: "${name}.service") daemons ++ [
          "wazuh-agent-auth.service"
        ];
      };

      services = mapAttrs mkService daemons // {
        wazuh-agent-auth = {
          description = "Enrolls the agent with the manager (once)";
          documentation = [
            "https://documentation.wazuh.com/${lib.versions.majorMinor cfg.package.version}/user-manual/reference/tools/agent-auth.html"
          ];
          after = [
            "setup-pre-wazuh.service"
            "network.target"
            "network-online.target"
          ];
          wants = [
            "setup-pre-wazuh.service"
            "network-online.target"
          ];
          before = mapAttrsToList (name: _: "${name}.service") daemons;
          environment = {
            WAZUH_HOME = stateDir;
          };

          unitConfig = {
            ConditionPathExists = "!${stateDir}/.agent-registered";
            RequiresMountsFor = [ stateDir ];
            # Manager outages are an external condition: retry every 5s
            # forever instead of parking the unit in failed state after
            # the default start rate limit trips.
            StartLimitIntervalSec = 0;
          };

          serviceConfig =
            let
              serverAddress = cfg.settings.client.server.address;
              port = cfg.settings.client.enrollment.port;
            in
            {
              Type = "oneshot";
              User = cfg.user;
              Group = cfg.group;
              Restart = "on-failure";
              RestartSec = "5s";
              ExecStart =
                let
                  authCmd =
                    "${cfg.package}/bin/agent-auth"
                    + " -m ${serverAddress} -p ${toString port}"
                    + lib.optionalString (cfg.agentAuthGroup != null) " -G ${cfg.agentAuthGroup}";
                in
                "${pkgs.writeShellScript "wazuh-agent-auth" ''
                  ${authCmd} && touch ${stateDir}/.agent-registered
                ''}";
            };
        };

        setup-pre-wazuh =
          let
            wazuhPreStart = pkgs.writeShellApplication {
              name = "wazuh-prestart";
              text = ''
                ${concatMapStringsSep "\n"
                  (
                    dir:
                    "[ -d ${stateDir}/${dir} ] || cp -Rv --no-preserve=ownership ${cfg.package}/${dir} ${stateDir}/${dir}"
                  )
                  [
                    "active-response"
                    "agentless"
                    "bin"
                    "etc"
                    "lib"
                    "logs"
                    "queue"
                    "tmp"
                    "var"
                    "wodles"
                  ]
                }

                chown -R ${cfg.user}:${cfg.group} ${stateDir}

                # NOTE: client.keys ends up wazuh-owned (the Wazuh
                # packages keep it root:wazuh): unprivileged agent-auth
                # must be able to write it during enrollment.

                # The tree is copied from the world-readable store — strip
                # world access so agent state (queues, logs, authd.pass)
                # stays agent-only.
                chmod -R u=rwX,g=rX,o= ${stateDir}

                # Real file, not a symlink — Wazuh's XML parser has issues with symlinks
                cp -f ${cfg.config} ${stateDir}/etc/ossec.conf
                chown ${cfg.user}:${cfg.group} ${stateDir}/etc/ossec.conf
                chmod 640 ${stateDir}/etc/ossec.conf

                ${lib.optionalString (cfg.agentAuthPassword != null) ''
                  umask 077
                  cp "${pkgs.writeText "wazuh-authd.pass" cfg.agentAuthPassword}" "${stateDir}/etc/authd.pass"
                  chmod 600 "${stateDir}/etc/authd.pass"
                  chown ${cfg.user}:${cfg.group} "${stateDir}/etc/authd.pass"
                ''}

              '';
            };
          in
          {
            description = "Initializes /var/ossec and deploys the generated ossec.conf";
            unitConfig.RequiresMountsFor = [ stateDir ];
            wantedBy = [ "wazuh-agent-auth.service" ];
            before = [ "wazuh-agent-auth.service" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = lib.getExe wazuhPreStart;
            };
          };
      };
    };
  };
}
