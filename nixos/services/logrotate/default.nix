{ config, lib, pkgs, ... }:

with lib;

let

  localDir = "/etc/local/logrotate";

  # This header is only used for user-/application-specific logrotate config
  # from /etc/local/logrotate/*. Platform currently uses the same defaults but
  # they have to be specified as sets (see below).
  userConfigHeader = ''
    # Global default options used for user-defined logrotate config.
    daily
    rotate 14
    create
    dateext
    delaycompress
    compress
    notifempty
    nomail
    noolddir
    missingok
    sharedscripts
  '';

  headerOverrideSettings = {
    rotate = 14;
    frequency = "daily";
  };

  platformSettings = {
    create = true;
    dateext = true;
    delaycompress = true;
    compress = true;
    notifempty = true;
    nomail = true;
    noolddir = true;
    missingok = true;
    sharedscripts = true;
  };

  readme = ''
    logrotate is enabled on this machine.

    You can put your application-specific logrotate snippets here
    and they will be executed regularly within the context of the
    owning user. Each service user must have a likewise named subdirectory, e.g.

    ${localDir}/s-myapp/myapp
    ${localDir}/s-otherapp/something
    ${localDir}/s-serviceuser/somethingelse

    We will also apply the following basic options by default:

    ${userConfigHeader}
  '';

  users = attrValues config.users.users;
  serviceUsers = builtins.filter (user: user.group == "service") users;

in

{
  options = {
    flyingcircus.logrotate.enable = lib.mkEnableOption ''
      automatic log rotation for system and user logfiles
    '';
  };

  config = lib.mkMerge [
    {
      systemd.tmpfiles.rules = [
        "d ${localDir} 0755 root root"
        "d /var/spool/logrotate 2775 root service"
      ];
    }

    (lib.mkIf config.flyingcircus.logrotate.enable {

      environment.etc = {
        "local/logrotate/README.txt".text = readme;
        # needed by user-logrotate.sh
        "logrotate.options".text = userConfigHeader;
        "current-config/logrotate.conf".source = config.services.logrotate.configFile;
      };

      environment.systemPackages = with pkgs; [
        logrotate
        (pkgs.writeScriptBin "logrotate-show-config" ''
          cat ${config.services.logrotate.configFile}
        '')
        (pkgs.writeScriptBin "fc-logrotate" ''
          logrotate "$@" ${config.services.logrotate.configFile}
        '')
      ];

      services.logrotate = {
        enable = true;
        settings = {
          # `header` is already defined by the upstream module.
          # We amend it here with our overrides.
          # The upstream modules merges the pieces together with recursiveUpdate:
          # 1. upstream settings
          # 2. our overrides
          # 3. { global = true; priority = 100; }
          # We have to watch upstream if additional defaults are added in the future.
          header = headerOverrideSettings;
          # Default priority is 1000 for sections added via .settings.*.
          # Our global settings are added before to be effective for those
          # sections so we use 900 (like mkPlatform) here.
          # Use a priority of 200 to place sections before our global settings
          # and 100 to place them even before the header.
          fcio = platformSettings // { global = true; priority = 900; };
        };
      };

      # We create one directory for each service user. I decided not to remove
      # old directories as this may be manually placed data that I don't want
      # to delete accidentally.
      flyingcircus.localConfigDirs = let
        cfgDir = u:
          lib.nameValuePair
            "logrotate-${u.name}"
            { dir = "${localDir}/${u.name}"; user = u.name; permissions = "0755"; };

        in listToAttrs (map cfgDir serviceUsers);

      systemd.services = {
        # XXX logrotate does not allow setting options and I need to rebuild the
        # command line here so we can get decent debugging output.
        logrotate = { ... }: {
          options = {
            script = lib.mkOption {
              apply = v: lib.replaceStrings [ "sbin/logrotate /nix" ] [ "sbin/logrotate -v /nix" ] v;
            };
          };
          config = {
            # Upstream puts logrotate in multi-user.target which triggers unwanted
            # service starts on fc-manage. It should only be activated by the timer.
             wantedBy = lib.mkForce [ ];
          };
        };
      } // listToAttrs (
        map (u: nameValuePair "user-logrotate-${u.name}" {
          description = "logrotate for ${u.name}";
          path = with pkgs; [ bash logrotate ];
          restartIfChanged = false;
          script = "${./user-logrotate.sh} ${localDir}/${u.name}";
          serviceConfig = {
            User = u.name;
            Type = "oneshot";
          };
          stopIfChanged = false;
        })
        serviceUsers);

      systemd.timers =
        listToAttrs (
          map (u: nameValuePair "user-logrotate-${u.name}" {
            description = "logrotate timer for ${u.name}";
            timerConfig = {
              OnCalendar = "*-*-* 00:01:00";
              RandomizedDelaySec = "15m";
            };
            wantedBy = [ "timers.target" ];
          })
          serviceUsers);

    })
  ];
}
