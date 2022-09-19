# Configure systemd journal access and local units.
{ config, lib, pkgs, ... }:

with lib;

let
  fclib = config.fclib;
  cfg = config.flyingcircus.systemd;
in
{
  options = with lib; {
    flyingcircus.systemd = {

      journalReadGroups = mkOption {
        description = "Groups that are allowed to read the system journal.";
        type = types.listOf types.string;
      };

    };
  };

  config = {

    flyingcircus.systemd.journalReadGroups = [
      "sudo-srv"
      "service"
      "admins"
    ];

    services.journald.extraConfig = ''
      SystemMaxUse=2G
      MaxLevelConsole=notice
      ForwardToWall=no
    '';

    services.journald.forwardToSyslog = lib.mkOverride 90 false;

    flyingcircus.activationScripts = {

      systemd-journal-acl = let
      mkSetfaclCmd = group: ''
        if [ $(getent group ${group}) ]; then
          ${pkgs.acl}/bin/setfacl -R -m g:${group}:rX -m d:g:${group}:rX /var/log/journal
        else
          echo "Warning: expected group '${group}' not found, skipping ACL."
        fi
      '';

      in {
        deps = [ "users" ];
        text = ''
          # Note: journald seems to change some permissions and the group if they
          # differ from its expectations for /var/log/journal.
          # Changing permissions via ACL like here is supported by journald.
          install -d -g systemd-journal /var/log/journal
        '' + lib.concatMapStringsSep "\n" mkSetfaclCmd cfg.journalReadGroups;
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
