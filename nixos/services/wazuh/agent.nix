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

  format = pkgs.formats.xml { withHeader = false; };

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
      # Journal access (logcollector's journald source) and network state,
      # granted per-service instead of user-wide so non-daemon processes
      # running as this user (e.g. agent-auth) don't carry them.
      SupplementaryGroups = [
        "systemd-journal"
        "systemd-network"
      ];
      WorkingDirectory = "${stateDir}/";
      # CAP_DAC_READ_SEARCH: read any file for FIM
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
        description = "Final `ossec.conf` configuration file used by wazuh";
        # Root element must be <ossec_config> — Wazuh's parser expects
        # exactly this tag name (the attrset key becomes the XML root).
        default = format.generate "ossec.conf" {
          ossec_config = filterNulls cfg.settings;
        };
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
                    Specifies the port to send events to the manager. This must match the associated listening port configured on the Wazuh manager.
                  '';
                  default = 1514;
                };
              };
              enrollment = {
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

          Enrollment runs only once per machine: after successful registration
          `wazuh-agent-auth` touches `/var/ossec/.agent-registered` and never
          runs again, so changing this value afterwards has no effect on an
          already enrolled agent.

          Note: this value is embedded in the Nix store and the generated
          system configuration, both of which are world-readable. It stays a
          stopgap until enrollment secrets can be provisioned through the
          platform secret (KV) store; the blast radius is limited to
          superfluous agent registrations on the manager. Set it only
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
        wantedBy = [ "multi-user.target" ];
        wants = forEach daemons (d: "${d}.service") ++ [ "wazuh-agent-auth.service" ];
      };

      services = (lib.genAttrs daemons (daemon: mkService daemon)) // {
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
              serverAddress = cfg.settings.client.server.address;
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

                # Tighten the copied tree: directories 0750, data files 0640,
                # executables keep 0750. Capital X applies +x only to
                # directories and to files that already carry an execute bit
                # (binaries/scripts shipped by the package).
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
            description = "Sets up wazuh's directory structure";
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
