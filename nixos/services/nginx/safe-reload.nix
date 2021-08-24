{ lib, config, pkgs, ... }:

with lib;

let
  cfg = config.services.nginx;

  configPath = "/etc/nginx/nginx.conf";

  runningPackagePath = "/etc/nginx/running-package";
  wantedPackagePath = "/etc/nginx/wanted-package";

  checkConfigCmd = ''${wantedPackagePath}/bin/nginx -t -c ${configPath}'';

  nginxCheckConfig = pkgs.writeScriptBin "nginx-check-config" ''
    #!${pkgs.runtimeShell}
    echo "Running built-in Nginx config validation (must pass in order to activate a config)..."
    ${checkConfigCmd} || exit 2
    echo "Running gixy security checker (just informational)..."
    ${pkgs.gixy}/bin/gixy ${configPath} || exit 1
  '';

  nginxReloadConfig = pkgs.writeScriptBin "nginx-reload" ''
    #!${pkgs.runtimeShell} -e
    echo "Reload triggered, checking config file..."
    # Check if the new config is valid
    ${checkConfigCmd} || rc=$?
    chown -R root:${cfg.group} /var/log/nginx
    if [[ -n $rc ]]; then
      echo "Error: Not restarting / reloading because of config errors."
      echo "New configuration not activated!"
      exit 1
    fi
    # Check if the package changed
    running_pkg=$(readlink -f ${runningPackagePath})
    wanted_pkg=$(readlink -f ${wantedPackagePath})
    if [[ $running_pkg != $wanted_pkg ]]; then
      echo "Nginx package changed: $running_pkg -> $wanted_pkg."
      ln -sfT $wanted_pkg ${runningPackagePath}
      if [[ -s /run/nginx/nginx.pid ]]; then
        if ${nginxReloadMaster}/bin/nginx-reload-master; then
          echo "Master process replacement completed."
        else
          echo "Master process replacement failed, trying again on next reload."
          ln -sfT $running_pkg ${runningPackagePath}
        fi
      else
        # We are still running an old version that didn't write a PID file or something is broken.
        # We can only force a restart now.
        echo "Warning: cannot replace master process because PID is missing. Restarting Nginx now..."
        kill -QUIT $MAINPID
      fi
    else
      # Package unchanged, we only need to change the configuration.
      echo "Reloading nginx config now."
      # Check journal for errors after the reload signal.
      datetime=$(date +'%Y-%m-%d %H:%M:%S')
      kill -HUP $MAINPID
      # Give Nginx some time to try changing the configuration.
      sleep 3
      if [[ $(journalctl --since="$datetime" -u nginx -q -g '\[emerg\]') != "" ]]; then
        echo "Warning: Possible failure when changing to new configuration."
        echo "This happens when changes to listen directives are incompatible with the running nginx master process."
        echo "Try systemctl restart nginx to activate the new config."
        exit 1
      fi
    fi
  '';
  nginxReloadMaster =
    pkgs.writeScriptBin "nginx-reload-master" ''
      #!${pkgs.runtimeShell} -e
      echo "Starting new nginx master process..."
      kill -USR2 $(< /run/nginx/nginx.pid)
      for x in {1..10}; do
          echo "Waiting for new master process to appear, try $x..."
          sleep 1
          if [[ -s /run/nginx/nginx.pid && -s /run/nginx/nginx.pid.oldbin ]]; then
              echo "Stopping old nginx workers..."
              kill -WINCH $(< /run/nginx/nginx.pid.oldbin)
              echo "Stopping old nginx master process..."
              kill -QUIT $(< /run/nginx/nginx.pid.oldbin)
              echo "Nginx master process replacement complete."
              exit 0
          fi
      done
      echo "Warning: new master process did not start."
      echo "This can be caused by changes to listen directives that are incompatible with the running nginx master process."
      echo "Check journalctl -eu nginx and try systemctl restart nginx to activate changes."
      exit 1
    '';
in
{
  environment.etc."nginx/wanted-package".source = cfg.package;

  environment.systemPackages = [ nginxReloadMaster nginxCheckConfig ];

  system.activationScripts.nginx-reload-check = lib.stringAfter [ "etc" ] ''
    if ${pkgs.procps}/bin/pgrep nginx &> /dev/null; then
      nginx_check_msg=$(${checkConfigCmd} 2>&1) || rc=$?
      if [[ -n $rc ]]; then
        printf "\033[0;31mWarning: \033[0mNginx config is invalid at this point:\n$nginx_check_msg\n"
        echo Reload may still work if missing Let\'s Encrypt SSL certs are the reason, for example.
        echo Please check the output of journalctl -eu nginx
      fi
    fi
  '';

  systemd.services.nginx = let
    preStartScript = pkgs.writeScript "nginx-pre-start" ''
      #!${pkgs.runtimeShell} -e
      ${cfg.preStart}
      ln -sfT $(readlink -f ${wantedPackagePath}) ${runningPackagePath}
      chown root:${cfg.group} -R /var/log/nginx
    '';

    capabilities = [
      "CAP_NET_BIND_SERVICE"
      "CAP_DAC_READ_SEARCH"
      "CAP_SYS_RESOURCE"
      "CAP_SETUID"
      "CAP_SETGID"
      "CAP_CHOWN"
    ];
  in {
    serviceConfig = {
      # modes
      RuntimeDirectoryMode = mkForce "0755";
      LogsDirectoryMode = mkForce "0755";
      UMask = mkForce null;
      CacheDirectory = mkForce null;
      CacheDirectoryMode = mkForce null;

      Type = "forking";
      PIDFile = "/run/nginx/nginx.pid";

      ExecStart = mkForce "${runningPackagePath}/bin/nginx -c ${configPath}";
      ExecStartPre = mkForce "+${preStartScript}";
      ExecReload = mkForce "+${nginxReloadConfig}/bin/nginx-reload";

      # User and group
      # XXX: We start nginx as root and drop later for compatibility reasons, this should change.
      User = mkForce null;

      # This limits the capabilities to the given list but does not grant anything by default.
      # Nginx does the right thing: it gives all of these capabilities to the
      # master process but none to the workers. This means that the master
      # can access certificates even if the permissions wouldn't allow it
      AmbientCapabilities = mkForce capabilities;
      CapabilityBoundingSet = mkForce capabilities;
      SystemCallFilter = mkForce "~@cpu-emulation @debug @keyring @mount @obsolete";
      RestrictNamespaces = mkForce null;

      # debug
      # SystemCallFilter = mkForce null;
      # ExecStart = mkForce "${pkgs.strace}/bin/strace ${runningPackagePath}/bin/nginx -c ${configPath}";
    };
  };
}
