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

      systemd-journal-acl = lib.stringAfter [ "systemd" ] ''
        # Ensure journal access for all users.
        chmod -R a+rX /var/log/journal
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
