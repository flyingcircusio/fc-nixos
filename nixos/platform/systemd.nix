# Configure systemd journal access and local units.
{ config, lib, pkgs, ... }:

with lib;

let
  fclib = config.fclib;
in
{
  config = {

    services.journald.extraConfig = ''
      SystemMaxUse=2G
      MaxLevelConsole=notice
      ForwardToWall=no
    '';

    services.journald.forwardToSyslog = lib.mkOverride 90 false;

    flyingcircus.activationScripts = {

      systemd-journal-acl = let
        journalReadGroups = [
          "sudo-srv"
          "service"
          "admins"
        ];
          acls =
            lib.concatMapStrings
              (group: "-m g:${group}:rX -m d:g:${group}:rX ")
              journalReadGroups;

        # setfacl requires all users and groups specified to exist already. Especially
        # after a fresh system installation that might not be always the case, so only
        # execute after succesful user and group creation.
        in {
          deps = [ "users" "etc" ];
          text = ''
            # Note: journald seems to change some permissions and the group if they
            # differ from its expectations for /var/log/journal.
            # Changing permissions via ACL like here is supported by journald.
            install -d -g systemd-journal /var/log/journal

            ${pkgs.acl}/bin/setfacl -R ${acls} /var/log/journal
          '';
        };

    };

    flyingcircus.localConfigDirs.systemd = {
      dir = "/etc/local/systemd";
    };

    systemd.extraConfig = ''
      DefaultRestartSec=3
      DefaultStartLimitInterval=60
      DefaultStartLimitBurst=5
    '';

    systemd.units =
      let
        unit_files = if (builtins.pathExists "/etc/local/systemd")
          then config.fclib.filesRel "/etc/local/systemd" else [];
        unit_configs = map
          (file: { "${file}" =
             { text = readFile ("/etc/local/systemd/" + file);
               wantedBy = [ "multi-user.target" ];};})
          unit_files;
      in zipAttrsWith (name: values: (last values)) unit_configs;

  };
}
