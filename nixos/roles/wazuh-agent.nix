# NOTE: Set the manager password in /run/wazuh-pass before enabling the role.
# The password is only needed for authenticating with the wazuh manager once.
# Other than that, the role works out-of-the-box.
# Just set flyingcircus.wazuh-agent.enable = true;
#
# Enrollment flow:
#   1. setup-pre-wazuh (root) — copies package state dirs, config, and auth password
#      into /var/ossec/. Runs only when wazuh-agent-auth is triggered.
#   2. wazuh-agent-auth (wazuh user) — runs `agent-auth` to register the agent
#      with the manager. Skipped if /var/ossec/.agent-registered exists.
#   3. Daemon services start.

{ config, lib, ... }:

let
  agentAuthPasswordFile = "/run/wazuh-pass";
  # Apply mkDefault to every leaf value in a nested attrset, so users can
  # override individual scalars at normal priority without discarding the
  # rest of the role defaults.
  mkDefaultDeep = lib.mapAttrsRecursive (_: lib.mkDefault);
  cfg = config.flyingcircus.roles.wazuh-agent;
in
{
  options.flyingcircus.roles.wazuh-agent = {
    enable = lib.mkEnableOption "Wazuh agent FC service wrapper";

    managerAddress = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "manage.fcwazuh.fcio.net";
      description = "IP address or hostname of the Wazuh manager.";
    };

    agentGroup = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = "VM";
      description = "Agent group assigned during enrollment.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Fail hard if the auth password file is missing.
    systemd.services.setup-pre-wazuh = {
      unitConfig.ConditionPathExists = agentAuthPasswordFile;
    };

    services.wazuh.agent = {
      enable = true;
      inherit agentAuthPasswordFile;
      agentAuthGroup = cfg.agentGroup;

      # Scalar defaults — each leaf wrapped in mkDefault (via mkDefaultDeep)
      # so users can override individual values at normal priority without
      # losing any other role default.
      settings = lib.mkMerge [
        (mkDefaultDeep {
          client = {
            server = {
              address = cfg.managerAddress;
              port = 1514;
              protocol = "tcp";
            };
            config-profile = "Linux";
            notify_time = 20;
            time-reconnect = 60;
            auto_restart = "yes";
            crypto_method = "aes";
          };

          client_buffer = {
            disabled = "no";
            queue_size = 5000;
            events_per_second = 500;
          };

          rootcheck = {
            disabled = "no";
            check_files = "yes";
            check_trojans = "yes";
            check_dev = "yes";
            check_sys = "yes";
            check_pids = "yes";
            check_ports = "yes";
            check_if = "yes";
            frequency = 43200;
            rootkit_files = "${config.services.wazuh.agent.package}/etc/shared/rootkit_files.txt";
            rootkit_trojans = "${config.services.wazuh.agent.package}/etc/shared/rootkit_trojans.txt";
            skip_nfs = "yes";
          };

          syscheck.disabled = "no";

          sca = {
            enabled = "yes";
            scan_on_start = "yes";
            interval = "12h";
            skip_nfs = "yes";
          };

          logging.log_format = "plain";
        })

        # List-valued defaults — set at normal priority (100), WITHOUT mkDefault.
        # The upstream module's freeformType (attrsOf xmlValue from
        # pkgs.formats.xml) CONCATENATES list definitions at equal priority
        # rather than replacing them. This means a user who writes
        # `services.wazuh.agent.settings.syscheck.directories = ["/srv/app"]`
        # AUTOMATICALLY EXTENDS the default `["/etc/local"]` — the result is
        # `["/etc/local" "/srv/app"]`, not a replacement. Same for localfile
        # and wodle (lists of attrsets → multiple XML elements).
        #
        # To REPLACE a default list entirely, use `lib.mkForce` on the
        # upstream setting.
        {
          syscheck.directories = [ "/etc/local" ];
          localfile = [
            {
              location = "journald";
              log_format = "journald";
            }
          ];
          wodle = [
            {
              "@name" = "syscollector";
              disabled = "no";
            }
          ];
        }
      ];
    };
  };
}
