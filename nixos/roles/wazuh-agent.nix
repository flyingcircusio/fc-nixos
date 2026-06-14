# FC role building on services.wazuh.agent.
# Our config is deliberately observe-only and runs as unprivileged user.
# See the service module for details.
{ config, lib, ... }:

let
  # Apply mkDefault to every leaf value in a nested attrset, so users can
  # override individual scalars at normal priority without discarding the
  # rest of the role defaults.
  mkDefaultDeep = lib.mapAttrsRecursive (_: lib.mkDefault);
  cfg = config.flyingcircus.roles.wazuh-agent;
in
{
  options.flyingcircus.roles.wazuh-agent = {
    enable = lib.mkEnableOption "Wazuh agent";

    managerAddress = lib.mkOption {
      type = lib.types.nonEmptyStr;
      description = "IP address or hostname of the Wazuh manager.";
    };

    agentAuthGroup = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = ''
        Agent group assigned during enrollment. Semantics as in
        services.wazuh.agent.agentAuthGroup.
      '';
    };

    agentAuthPassword = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = ''
        Password for the manager auth service, used once for initial
        enrollment. Semantics and the world-readable caveat as in
        services.wazuh.agent.agentAuthPassword.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.wazuh.agent = {
      enable = true;
      inherit (cfg) agentAuthGroup agentAuthPassword;

      settings = lib.mkMerge [
        # Upstream defaults pinned explicitly, so Wazuh upgrades don't
        # silently change agent behavior. Deviations are commented.
        (mkDefaultDeep {
          client = {
            server = {
              address = cfg.managerAddress;
              port = 1514;
              protocol = "tcp";
            };
            # Matches the profile blocks of the centralized agent.conf
            # served by the Wazuh manager.
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
            # Explicit on purpose: the daemons have no built-in default
            # for these paths — without the keys syscheckd silently skips
            # the rootkit file/trojan checks.
            rootkit_files = "${config.services.wazuh.agent.package}/etc/shared/rootkit_files.txt";
            rootkit_trojans = "${config.services.wazuh.agent.package}/etc/shared/rootkit_trojans.txt";
            skip_nfs = "yes";
          };

          syscheck.disabled = "no";

          sca = {
            enabled = "yes";
            scan_on_start = "yes";
            # Deviation from the compiled-in default (24h, WM_DEF_INTERVAL):
            # FC pins a tighter 12h SCA cycle.
            interval = "12h";
            skip_nfs = "yes";
          };

          logging.log_format = "plain";
        })

        # FC platform baseline (normal priority — override with mkForce):
        # FIM on /etc/local, journald as log source, system inventory on.
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
