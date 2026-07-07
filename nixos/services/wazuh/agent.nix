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
    forEach
    nameValuePair
    listToAttrs
    concatMapStringsSep
    filterAttrsRecursive
    types
    ;

  # Filter null values from settings to avoid empty XML elements
  # Wazuh's XML parser doesn't handle <tag></tag> well for optional fields
  filterNulls = filterAttrsRecursive (_: v: v != null);

  xmlValue = (pkgs.formats.xml { }).type;

  #TODO Make this an option either at the top level or under `settings`
  stateDir = "/var/ossec";
  cfg = config.services.wazuh.agent;

  daemons = [
    "wazuh-modulesd"
    "wazuh-logcollector"
    "wazuh-syscheckd"
    "wazuh-agentd"
    "wazuh-execd"
  ];

  mkService = d: {
    description = "${d}";

    # Must wait for setup to complete before starting
    # Using wants+after ensures setup runs first without hard dependency
    wants = [ "setup-pre-wazuh.service" ];
    after = [ "setup-pre-wazuh.service" ];

    partOf = [ "wazuh.target" ];
    #TODO Why is `/run/current-system` added - is it required for security scanning?
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
      WorkingDirectory = "${stateDir}/";
      # CAP_DAC_READ_SEARCH: read any file for FIM
      # AmbientCapabilities passes capabilities to non-root user
      AmbientCapabilities = [
        "CAP_DAC_READ_SEARCH"
        "CAP_NET_BIND_SERVICE"
      ];
      CapabilityBoundingSet = [
        "CAP_DAC_READ_SEARCH"
        "CAP_NET_BIND_SERVICE"
      ];

      ExecStart = "${cfg.package}/bin/${d} -f";
    };
  };
in
{
  options = {
    services.wazuh.agent = {
      enable = mkEnableOption "Wazuh agent";
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
        #TODO Should this be RO?
        description = ''
          Final `ossec.conf` configuration file used by wazuh
        '';
        # Generate XML without prolog - Wazuh's parser doesn't like <?xml...?>
        default = pkgs.writeText "ossec.conf" (
          let
            xmlWithProlog = (pkgs.formats.xml { }).generate "ossec.conf" {
              ossec_config = filterNulls cfg.settings;
            };
            xmlContent = builtins.readFile xmlWithProlog;
            # Remove XML prolog line
            xmlWithoutProlog = lib.removePrefix ''
              <?xml version="1.0" encoding="utf-8"?>
            '' xmlContent;
          in
          # Add Wazuh-style comment header
          "<!--  Wazuh - Agent - NixOS generated configuration  -->${xmlWithoutProlog}"
        );
        defaultText = "Generated XML configuration";
      };

      #TODO determine which options are necessary for a default installation, which should have typing/be accessible always (e.g. port options)
      #TODO Determine if settings included as options here are only a selection or if they can be generated systematically from the Wazuh documentation
      settings = mkOption {
        default = { };
        description = ''
          Wazuh-agent configuration written in Nix. This will be serialized to XML and passed as `ossec.conf`

          Note that the root `ossec_config` tag is added automatically

          Not all possible configuration options are listed here - see the [config reference](https://documentation.wazuh.com/${cfg.package.version}/user-manual/reference/ossec-conf/index.html) for possible values
        '';
        type = types.submodule {
          freeformType = types.attrsOf xmlValue;

          options = {
            client = {
              server = {
                address = mkOption {
                  type = types.nullOr types.nonEmptyStr;
                  description = ''
                    Specifies the IP address or the hostname of the Wazuh manager.
                  '';
                  example = "192.168.1.2";
                  default = null;
                };
                port = mkOption {
                  type = types.port;
                  description = ''
                    Specifies the port to send events to the manager. This must match the associated listening port configured on the Wazuh manager.
                  '';
                  default = 1514;
                };
              };
              enrollment = {
                manager_address = mkOption {
                  type = types.nullOr types.nonEmptyStr;
                  description = ''
                    Hostname or IP address of the manager where the agent will be enrolled. If no value is set, the agent will try enrolling to the same manager that was specified for connection.
                  '';
                  example = "192.168.1.2";
                  default = null;
                };
                port = mkOption {
                  type = types.port;
                  description = ''
                    Specifies the port on the manager to send enrollment request. This must match the associated listening port configured on the Wazuh manager.
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
          These can be removed/overridden with `lib.mkForce`
          To add additional packages, use `services.wazuh.agent.extraPackages` instead
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
          Password for the auth service.

          Written to `/var/ossec/etc/authd.pass` by `setup-pre-wazuh` and used
          for initial enrollment with the manager.

          Note: this value is embedded in the Nix store and the generated
          system configuration, both of which are world-readable. Set it only
          if that exposure is acceptable.
        '';
      };

      agentAuthGroup = mkOption {
        type = types.nullOr types.nonEmptyStr;
        default = null;
        description = ''
          Agent group assigned during enrollment (`-G` flag to agent-auth).
          The agent will be added to this group on the manager after registration.
        '';
        example = "VM";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.settings.client.server.address != null;
        message = "services.wazuh.agent.settings.client.server.address must be set";
      }

    ];

    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
      #TODO Determine if the agent should use a separate user than the other microservices
      description = "Wazuh agent user";
      home = stateDir;
      #TODO This should be set as `SupplementaryGroups` in the systemd service config if only specific daemons need the capabilities
      extraGroups = [
        "systemd-journal"
        "systemd-network"
      ]; # To read journal entries and network state
    };

    users.groups.${cfg.group} = { };

    systemd = {
      tmpfiles.rules = [
        "d ${stateDir}/tmp 0750 ${cfg.user} ${cfg.group} 1d"
      ];
      targets = {
        multi-user.wants = [ "wazuh.target" ];
        wazuh.wants = forEach daemons (d: "${d}.service") ++ [ "wazuh-agent-auth.service" ];
      };

      services = listToAttrs (map (daemon: nameValuePair daemon (mkService daemon)) daemons) // {
        wazuh-agent-auth = {
          description = "Sets up wazuh agent auth";
          after = [
            "setup-pre-wazuh.service"
            "network.target"
            "network-online.target"
          ];
          wants = [
            "setup-pre-wazuh.service"
            "network-online.target"
          ];
          before = map (d: "${d}.service") daemons;
          environment = {
            WAZUH_HOME = stateDir;
          };

          unitConfig = {
            ConditionPathExists = "!${stateDir}/.agent-registered";
          };

          serviceConfig =
            let
              enrollmentAddress = cfg.settings.client.enrollment.manager_address;
              serverAddress = cfg.settings.client.server.address;
              ip = if enrollmentAddress != null then enrollmentAddress else serverAddress;
              port = cfg.settings.client.enrollment.port;
            in
            {
              Type = "oneshot";
              User = cfg.user;
              Group = cfg.group;
              ExecStart =
                let
                  authCmd =
                    "${cfg.package}/bin/agent-auth"
                    + " -m ${ip} -p ${toString port}"
                    + lib.optionalString (cfg.agentAuthGroup != null) " -G ${cfg.agentAuthGroup}";
                in
                "${pkgs.writeShellScript "wazuh-agent-auth" ''
                  ${authCmd} && touch ${stateDir}/.agent-registered
                ''}";
            };
        };

        setup-pre-wazuh = {
          description = "Sets up wazuh's directory structure";
          wantedBy = [ "wazuh-agent-auth.service" ];
          before = [ "wazuh-agent-auth.service" ];
          serviceConfig = {
            Type = "oneshot";
            # Run as root to create /var/ossec directory structure
            ExecStart = "${pkgs.writeShellScriptBin "wazuh-prestart" ''
              set -euo pipefail

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

              find ${stateDir} -type d -exec chmod 770 {} \;
              find ${stateDir} -type f -exec chmod 750 {} \;

              # Copy ossec.conf as real file (Wazuh's XML parser has issues with symlinks)
              cp -f ${cfg.config} ${stateDir}/etc/ossec.conf

              # Write auth password (skip if unset — e.g., already enrolled agent).
              # `pkgs.writeText` materializes the password as a store path that
              # setup-pre-wazuh copies into place with restrictive permissions.
              # The password is therefore world-readable in the store — see the
              # option description for the trade-off.
              ${lib.optionalString (cfg.agentAuthPassword != null) ''
                umask 077
                cp "${pkgs.writeText "wazuh-authd.pass" cfg.agentAuthPassword}" "${stateDir}/etc/authd.pass"
                chmod 600 "${stateDir}/etc/authd.pass"
                chown ${cfg.user}:${cfg.group} "${stateDir}/etc/authd.pass"
              ''}

            ''}/bin/wazuh-prestart";
          };
        };
      };
    };
  };
}
