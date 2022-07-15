{ config, lib, pkgs, ... }:

with lib;

let
  localDir = "/etc/local/logrotate";

  globalOptions = ''
    # Global default options for the Flying Circus platform.
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

  readme = ''
    logrotate is enabled on this machine.

    You can put your application-specific logrotate snippets here
    and they will be executed regularly within the context of the
    owning user. Each service user must have a likewise named subdirectory, e.g.

    ${localDir}/s-myapp/myapp
    ${localDir}/s-otherapp/something
    ${localDir}/s-serviceuser/somethingelse

    We will also apply the following basic options by default:

    ${globalOptions}
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
        "logrotate.options".text = globalOptions;
      };

      environment.systemPackages = with pkgs; [
        logrotate
        (pkgs.writeScriptBin "logrotate-config-file" ''
          grep exec $(systemctl cat logrotate | grep ExecStart= | cut -f 2 -d=) | cut -f 4 -d" "
        '')
      ];

      services.logrotate = {
        enable = true;
        extraConfig = mkOrder 50 globalOptions;
        checkConfig = false;
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
