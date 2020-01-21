# Configure systemd journal access and local units.
{ config, lib, pkgs, ... }:

with lib;

let
  fclib = config.fclib;
in
{
  config = {

    services.journald.extraConfig = ''
      SystemMaxUse=1G
      MaxLevelConsole=notice
      ForwardToSyslog=true
    '';

    flyingcircus.activationScripts = {

      systemd-journal-acl = let
        # wheel is allowed to see the journal by default, we add some groups
        journalReadGroups = [
          "wheel"
          "sudo-srv"
          "service"
          "admins"
        ];
        acl =
          lib.concatMapStringsSep
            ","
            (group: "g:${group}:rx,d:g:${group}:rx")
            journalReadGroups;

      in ''
        # Note: journald seems to change some permissions and the group if they
        # differ from its expectations for /var/log/journal.
        # Changing permissions via ACL like here is supported by journald.

        # Create journal dir if it's missing.
        mkdir /var/log/journal 2> /dev/null || true
        # Reset permissions that were granted in earlier versions.
        chmod -R 640 /var/log/journal/*/* 2> /dev/null || true
        # Ensure journal read access for some groups
        ${pkgs.acl}/bin/setfacl -Rnm ${acl} /var/log/journal
      '';

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
