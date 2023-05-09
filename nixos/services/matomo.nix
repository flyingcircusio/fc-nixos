{ config, lib, options, pkgs, ... }:
with lib;
let
  cfg = config.services.matomo;
  fpm = config.services.phpfpm.pools.${pool};

  user = "matomo";

  pool = user;
  phpExecutionUnit = "phpfpm-${pool}";
  databaseService = "mysql.service";

  phpPackage = pkgs.php82;

  fqdn = if config.networking.domain != null then config.networking.fqdn else config.networking.hostName;

  dataDir = "/var/lib/${user}";
  # Additional Plugins installed locally by a service user (deployment).
  # This is intentionally not in the webroot dir because it doesn't have to be
  # accessed by Nginx and Matomo can handle relative paths to plugin dirs outside
  # of the webroot.
  extraPluginsDir = "${dataDir}/plugins";
  webrootDir = "${dataDir}/share";

  configDir = "${webrootDir}/config";
  configIniPhpFile = "${configDir}/config.ini.php";
  # Plugins distributed with Matomo.
  corePluginsDir = "${webrootDir}/plugins";
  jsDir = "${webrootDir}/js";
  matomoTrackerFile = "${webrootDir}/matomo.js";
  miscDir = "${webrootDir}/misc";
  piwikTrackerFile = "${webrootDir}/piwik.js";
  tmpDir = "${webrootDir}/tmp";

  # In general, we give Matomo read access only to the data directory.
  # Matomo wants to write to some paths, either from the main application or
  # matomo-console.
  # https://matomo.org/faq/on-premise/how-to-configure-matomo-for-security/
  matomoReadWritePaths = [
    # JS tracker files need to be modified when activating some plugins.
    # The command matomo-console custom-matomo-js:update also writes these files.
    matomoTrackerFile
    piwikTrackerFile
    # The config.ini.php is created by the interactive installer (Web UI) in this directory.
    configDir
    "${miscDir}/user"
    # Not mentioned by the Matomo FAQ but needed for tagmanager.
    # tagmanager uses this directory to create container_*.js files.
    jsDir
    # Temporary files created by Matomo.
    tmpDir
    # Not mentioned by the Matomo FAQ but it's needed for updating the GeoIP database from the UI
    # or automatically.
    miscDir
  ];

  nginxReadPaths = [
    corePluginsDir
    jsDir
  ];

  serviceGroupReadWritePaths = [
    extraPluginsDir
  ];

  pluginDirs = [
    "${extraPluginsDir}/;../plugins"
    "${corePluginsDir}/;plugins"
  ];

  matomoPathExtra = [ pkgs.gawk pkgs.procps ];

  environment = {
    MATOMO_PLUGIN_DIRS = lib.concatStringsSep ":" pluginDirs;
    # We disable installing plugins via the UI by default by if someone
    # activates it, we should put plugins in a separated and writable directory.
    MATOMO_PLUGIN_COPY_DIR = "${extraPluginsDir}/";
  };

  phpEnv = mapAttrs (n: v: "'${v}'") (environment // {
    PATH = lib.makeBinPath matomoPathExtra;
  });

  matomoCheckPermissions = pkgs.writeShellApplication {
    runtimeInputs = [ pkgs.acl ];
    name = "matomo-check-permissions";
    text = ''
      set -x
      getfacl /var/lib/matomo/plugins
      getfacl /var/lib/matomo
      getfacl /var/lib/matomo/share
      getfacl /var/lib/matomo/share/js
      getfacl /var/lib/matomo/share/plugins
      sudo -u nginx stat /var/lib/matomo/share/matomo.js
      sudo -u nginx stat /var/lib/matomo/share/piwik.js
      sudo -u nginx stat /var/lib/matomo/share/js/piwik.js
      sudo -u nginx stat /var/lib/matomo/share/plugins/CoreHome/images/favicon.ico
    '';
  };

in {
  imports = [
    (mkRenamedOptionModule [ "services" "piwik" "enable" ] [ "services" "matomo" "enable" ])
    (mkRenamedOptionModule [ "services" "piwik" "webServerUser" ] [ "services" "matomo" "webServerUser" ])
    (mkRemovedOptionModule [ "services" "piwik" "phpfpmProcessManagerConfig" ] "Use services.phpfpm.pools.<name>.settings")
    (mkRemovedOptionModule [ "services" "matomo" "phpfpmProcessManagerConfig" ] "Use services.phpfpm.pools.<name>.settings")
    (mkRenamedOptionModule [ "services" "piwik" "nginx" ] [ "services" "matomo" "nginx" ])
    (mkRenamedOptionModule [ "services" "matomo" "periodicArchiveProcessingUrl" ] [ "services" "matomo" "hostname" ])
  ];

  options = {
    services.matomo = {
      # NixOS PR for database setup: https://github.com/NixOS/nixpkgs/pull/6963
      # Matomo issue for automatic Matomo setup: https://github.com/matomo-org/matomo/issues/10257
      # TODO: find a nice way to do this when more NixOS MySQL and / or Matomo automatic setup stuff is implemented.
      enable = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          Enable Matomo web analytics with php-fpm backend.
          Either the nginx option or the webServerUser option is mandatory.
        '';
      };

      package = mkOption {
        type = types.package;
        description = lib.mdDoc ''
          Matomo package for the service to use.
          This can be used to point to newer releases from nixos-unstable,
          as they don't get backported if they are not security-relevant.
        '';
        default = pkgs.matomo;
        defaultText = literalExpression "pkgs.matomo";
      };

      webServerUser = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "lighttpd";
        description = lib.mdDoc ''
          Name of the web server user that forwards requests to {option}`services.phpfpm.pools.<name>.socket` the fastcgi socket for Matomo if the nginx
          option is not used. Either this option or the nginx option is mandatory.
          If you want to use another webserver than nginx, you need to set this to that server's user
          and pass fastcgi requests to `index.php`, `matomo.php` and `piwik.php` (legacy name) to this socket.
        '';
      };

      periodicArchiveProcessing = mkOption {
        type = types.bool;
        default = true;
        description = lib.mdDoc ''
          Enable periodic archive processing, which generates aggregated reports from the visits.

          This means that you can safely disable browser triggers for Matomo archiving,
          and safely enable to delete old visitor logs.
          Before deleting visitor logs,
          make sure though that you run `systemctl start matomo-archive-processing.service`
          at least once without errors if you have already collected data before.
        '';
      };

      hostname = mkOption {
        type = types.str;
        default = "${user}.${fqdn}";
        defaultText = literalExpression ''
          if config.${options.networking.domain} != null
          then "${user}.''${config.${options.networking.fqdn}}"
          else "${user}.''${config.${options.networking.hostName}}"
        '';
        example = "matomo.yourdomain.org";
        description = lib.mdDoc ''
          URL of the host, without https prefix. You may want to change it if you
          run Matomo on a different URL than matomo.yourdomain.
        '';
      };

      memoryLimit = mkOption {
        type = types.ints.positive;
        description = ''
          Memory limit for the PHP processes in MiB.
        '';
        default = 1024;
      };

      nginx = mkOption {
        type = types.nullOr (types.submodule (
          recursiveUpdate
            (import ./nginx/vhost-options.nix { inherit config lib; })
            {
              # enable encryption by default,
              # as sensitive login and Matomo data should not be transmitted in clear text.
              options.forceSSL.default = true;
              options.enableACME.default = true;
            }
        )
        );
        default = null;
        example = literalExpression ''
          {
            serverAliases = [
              "matomo.''${config.networking.domain}"
              "stats.''${config.networking.domain}"
            ];
            enableACME = false;
          }
        '';
        description = lib.mdDoc ''
            With this option, you can customize an nginx virtualHost which already has sensible defaults for Matomo.
            Either this option or the webServerUser option is mandatory.
            Set this to {} to just enable the virtualHost if you don't need any customization.
            If enabled, then by default, the {option}`serverName` is
            `''${user}.''${config.networking.hostName}.''${config.networking.domain}`,
            SSL is active, and certificates are acquired via ACME.
            If this is set to null (the default), no nginx virtualHost will be configured.
        '';
      };

      tools = {
        matomoConsole = mkOption {
          type = types.package;
          internal = true;
          default = pkgs.writeShellScriptBin "matomo-console" ''
            ${phpPackage}/bin/php ${webrootDir}/console "$@"
          '';
        };
        matomoCheckPermissions = mkOption {
          type = types.package;
          internal = true;
          default = matomoCheckPermissions;
        };
      };


    };
  };

  config = mkIf cfg.enable {
    warnings = mkIf (cfg.nginx != null && cfg.webServerUser != null) [
      "If services.matomo.nginx is set, services.matomo.nginx.webServerUser is ignored and should be removed."
    ];

    assertions = [ {
        assertion = cfg.nginx != null || cfg.webServerUser != null;
        message = "Either services.matomo.nginx or services.matomo.nginx.webServerUser is mandatory";
    }];

    environment.systemPackages = [
      cfg.tools.matomoConsole
      cfg.tools.matomoCheckPermissions
    ];

    users.users.${user} = {
      isSystemUser = true;
      createHome = true;
      home = "${dataDir}/home";
      group  = user;
    };
    users.groups.${user} = {};

    services.percona.extraOptions = ''
      local-infile = 1
    '';

    systemd.services.matomo-setup-update = {
      # everything needs to set up and up to date before Matomo php files are executed
      partOf = [ "${phpExecutionUnit}.service" ];
      before = [ "${phpExecutionUnit}.service" ];
      # The update part of the script can only work if the database is already up and running.
      # We cannot require that we have a local database because the db location can be configured
      # via the Matomo UI but we should start it, if it's here. Systemd ignores the wants/after
      # relationships if there's no local mysql service. Using requires here would fail in that case.
      wants = [ databaseService ];
      after = [ databaseService ];
      path = [ cfg.package pkgs.acl cfg.tools.matomoConsole ];
      inherit environment;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        restartIfChanged = true;
        User = user;
        # hide especially config.ini.php from other
        UMask = "0007";
        ExecStartPre = let
          preStartScript = pkgs.writeShellScript "matomo-setup-update-pre" ''
            # Note that ${configIniPhpFile} might contain the MySQL password.
            # Use User-Private Group scheme to protect Matomo data, but allow administration / backup via 'matomo' group

            echo "Setting up Matomo data dir ${dataDir}."
            echo "Web root is at ${webrootDir}".

            mkdir -p ${webrootDir}

            echo "Checking if data migration from older matomo installations is needed..."

            if [ -d ${dataDir}/config ]; then
              echo "Migrating config from old location ${dataDir}/config"
              mkdir -p ${configDir}
              mv ${dataDir}/config/* ${configDir}/
              rm ${dataDir}/config/.htaccess
              rmdir ${dataDir}/config
            fi

            if [ -d ${dataDir}/misc ]; then
              echo "Migrating misc data from old location ${dataDir}/misc"
              mkdir -p ${miscDir}
              mv ${dataDir}/misc/* ${miscDir}/
              rmdir ${dataDir}/misc
            fi

            if [ -d ${dataDir}/tagmanager ]; then
              echo "Migrating tagmanager data from old location ${dataDir}/tagmanager"
              mkdir -p ${jsDir}
              mv ${dataDir}/tagmanager/* ${jsDir}/
              rmdir ${dataDir}/tagmanager
            fi

            if [ -f ${dataDir}/matomo.js ]; then
              echo "Cleaning up old matomo.js"
              rm ${dataDir}/matomo.js
            fi

            if [ -d ${dataDir}/tmp ]; then
              echo "Cleaning up old tmpdir"
              rm -rf ${dataDir}/tmp
            fi

            mkdir -p ${extraPluginsDir}
            chown ${user}:${user} ${extraPluginsDir}

            CURRENT_PACKAGE=$(readlink ${dataDir}/current-package || true)
            NEW_PACKAGE=${cfg.package}

            echo "Currently used package: $CURRENT_PACKAGE"
            echo "Possibly new package:   $NEW_PACKAGE"

            if [ "$CURRENT_PACKAGE" == "$NEW_PACKAGE" ]; then
              echo "Package is unchanged."
            else
              echo "Package updated, installing new files to ${dataDir}..."

              cp -r ${cfg.package}/share/* ${webrootDir}/
              echo "Copied files, updating package link in ${dataDir}/current-package."
              ln -sfT ${cfg.package} ${dataDir}/current-package

              if [[ -f ${configIniPhpFile} ]]; then
                echo "Clearing caches..."
                matomo-console cache:clear
              fi
            fi

            mkdir -p ${tmpDir}

            # Reset ACLs to avoid surprises, especially when upgrading from
            # pre-role Matomo.
            setfacl -Rb ${dataDir}

            # matomo user owns the data directory.
            chown -R ${user}:${user} ${dataDir}

            # matomo user is allowed to read everything in the data dir.
            chmod -R u=rX,g=rX,o= ${dataDir}

            echo "Giving matomo read+write access to ${lib.concatStringsSep ", " matomoReadWritePaths}"
            chmod -R u+wX,g+wX \
              ${lib.concatStringsSep " \\\n  " matomoReadWritePaths}

            # Set masks for directories where we want to use ACLs that extend
            # permissions to other users.
            setfacl -Rm m:x ${dataDir}
            setfacl -Rm m:rx ${jsDir} ${corePluginsDir}
            setfacl -Rm m:rwx ${extraPluginsDir}

            # Nginx must be able to read files from some locations in the Matomo data dir.

            echo "Giving nginx x dir access to the web root at ${webrootDir}."
            setfacl -m u:nginx:x ${dataDir} ${webrootDir}

            echo "Giving nginx read access to ${lib.concatStringsSep ", " nginxReadPaths}"
            setfacl -Rm u:nginx:rX ${lib.concatStringsSep " " nginxReadPaths}
            setfacl -Rm d:u:nginx:rX ${lib.concatStringsSep " " nginxReadPaths}

            # Service users must be able to add plugin bundles.
            setfacl -m g:service:x ${dataDir}

            echo "Giving service users write access to ${lib.concatStringsSep ", " serviceGroupReadWritePaths}"
            setfacl -Rm g:service:rwX ${lib.concatStringsSep " " serviceGroupReadWritePaths}
            setfacl -Rm d:g:service:rwX ${lib.concatStringsSep " " serviceGroupReadWritePaths}
            chmod g+s ${lib.concatStringsSep " " serviceGroupReadWritePaths}
          '';
        in [ "+${preStartScript}" ];
      };

      script = ''
        # Check whether user setup has already been done.
        echo "Checking main config file ${configIniPhpFile}..."
        if [[ -f ${configIniPhpFile} ]]; then
          echo "${configIniPhpFile} already exists, looks like Matomo is already installed."
          echo "Executing possibly pending database updates..."
          matomo-console core:update --yes
          echo "Updating ${matomoTrackerFile}..."
          matomo-console custom-matomo-js:update
          echo "Updating ${piwikTrackerFile}..."
          matomo-console custom-piwik-js:update

          echo "Checking settings in ${configIniPhpFile}..."

          if ! grep "force_ssl" ${configIniPhpFile}; then
            echo "Adding force_ssl = 1 to the config file."
            sed -i '/\[General\]/a force_ssl = 1' ${configIniPhpFile}
          fi

          if ! grep "enable_auto_update" ${configIniPhpFile}; then
            echo "Adding enable_auto_update = 0 to the config file (disables updates and plugin installations via UI)."
            sed -i '/\[General\]/a enable_auto_update = 0' ${configIniPhpFile}
          fi
        else
          echo "No ${configIniPhpFile} found, looks like the first run of Matomo."
          echo "Matomo must be set up using the Web installer: https://${cfg.hostname}"
        fi

        setfacl -m u:nginx:r ${matomoTrackerFile}
        setfacl -m u:nginx:r ${piwikTrackerFile}
      '';
    };

    # If this is run regularly via the timer,
    # 'Browser trigger archiving' can be disabled in Matomo UI > Settings > General Settings.
    systemd.services.matomo-archive-processing = {
      description = "Archive Matomo reports";
      # The update part of the script can only work if the database is already up and running.
      # We cannot require that we have a local database because the db location can be configured
      # via the Matomo UI but we should start it, if it's here. Systemd ignores the wants/after
      # relationships if there's no local mysql service. Using requires here would fail in that case.
      wants = [ databaseService ];
      after = [ databaseService ];
      path = matomoPathExtra;
      inherit environment;

      serviceConfig = {
        Type = "oneshot";
        User = user;
        UMask = "0007";
        CPUSchedulingPolicy = "idle";
        IOSchedulingClass = "idle";
        ExecStart = "${cfg.tools.matomoConsole}/bin/matomo-console core:archive --url=https://${cfg.hostname}";
      };

      unitConfig = {
        ConditionPathExists = configIniPhpFile;
      };
    };

    systemd.timers.matomo-archive-processing = mkIf cfg.periodicArchiveProcessing {
      description = "Automatically archive Matomo reports every hour";

      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = "yes";
        AccuracySec = "10m";
      };
    };

    systemd.services.${phpExecutionUnit} = {
      requires = [ "matomo-setup-update.service" ];
      # stop phpfpm on package upgrade, do database upgrade via matomo-setup-update, and then restart
      restartTriggers = [ cfg.package ];
      restartIfChanged = true;
      # Make sure that secret files like config.ini.php which are written by Matomo
      # don't get read permission for other users.
      serviceConfig.UMask = "0007";
    };

    services.phpfpm.pools = let
      # workaround for when both are null and need to generate a string,
      # which is illegal, but as assertions apparently are being triggered *after* config generation,
      # we have to avoid already throwing errors at this previous stage.
      socketOwner = if (cfg.nginx != null) then config.services.nginx.user
      else if (cfg.webServerUser != null) then cfg.webServerUser else "";
    in {
      ${pool} = {
        inherit user;
        phpOptions = ''
          error_log = 'stderr'
          log_errors = on
          memory_limit = ${toString cfg.memoryLimit}M
          # Settings to make the SecurityInfo plugin happy.
          open_basedir = "${dataDir}"
          upload_tmp_dir = "${tmpDir}"
          expose_php = off
          # This path doesn't exist and is not needed for Matomo but SecurityInfo
          # wants this setting.
          session.save_path = "${dataDir}/sessions/"
        '';

        inherit phpPackage;
        settings = mapAttrs (name: mkDefault) {
          "listen.owner" = socketOwner;
          "listen.group" = "root";
          "listen.mode" = "0660";
          "pm" = "dynamic";
          "pm.max_children" = 75;
          "pm.start_servers" = 10;
          "pm.min_spare_servers" = 5;
          "pm.max_spare_servers" = 20;
          "pm.max_requests" = 500;
          "catch_workers_output" = true;
        };
        inherit phpEnv;
      };
    };

    services.nginx.virtualHosts = mkIf (cfg.nginx != null) {
      # References:
      # https://fralef.me/piwik-hardening-with-nginx-and-php-fpm.html
      # https://github.com/perusio/piwik-nginx
      "${cfg.hostname}" = mkMerge [ cfg.nginx {
        # don't allow to override the root easily, as it will almost certainly break Matomo.
        # disadvantage: not shown as default in docs.
        root = mkForce webrootDir;

        # define locations here instead of as the submodule option's default
        # so that they can easily be extended with additional locations if required
        # without needing to redefine the Matomo ones.
        # disadvantage: not shown as default in docs.
        locations."/" = {
          index = "index.php";
        };
        # allow index.php for webinterface
        locations."= /index.php".extraConfig = ''
          fastcgi_pass unix:${fpm.socket};
        '';
        # allow matomo.php for tracking
        locations."= /matomo.php".extraConfig = ''
          fastcgi_pass unix:${fpm.socket};
        '';
        # allow piwik.php for tracking (deprecated name)
        locations."= /piwik.php".extraConfig = ''
          fastcgi_pass unix:${fpm.socket};
        '';
        # Any other attempt to access any php files is forbidden
        locations."~* ^.+\\.php$".extraConfig = ''
          return 403;
        '';
        # Disallow access to unneeded directories
        locations."~ ^/(?:config|core|lang|misc|tmp)/".extraConfig = ''
          return 403;
        '';
        # Disallow access to several helper files
        locations."~* \\.(?:bat|git|ini|sh|txt|tpl|xml|md)$".extraConfig = ''
          return 403;
        '';
        # No crawling of this site for bots that obey robots.txt - no useful information here.
        locations."= /robots.txt".extraConfig = ''
          return 200 "User-agent: *\nDisallow: /\n";
        '';
        # let browsers cache matomo.js
        locations."= /matomo.js".extraConfig = ''
          expires 1M;
        '';
        # let browsers cache piwik.js (deprecated name)
        locations."= /piwik.js".extraConfig = ''
          expires 1M;
        '';
        # Alias for the previous Tag Manager container location which
        # may still be in use by tracked applications because the old
        # path is embedded in the tracking code.
        locations."/js/tagmanager/" = {
            alias = "${jsDir}/";
        };
      }];
    };
  };
}
